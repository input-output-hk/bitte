{
  config,
  pkgs,
  lib,
  hashiTokens,
  ...
}: let
  cfg = config.services.vault-snapshots;

  inherit (lib) boolToString mkEnableOption mkIf mkOption;
  inherit (lib.types) addCheck attrs bool int str submodule;

  snapshotJobConfig = submodule {
    options = {
      enable = mkOption {
        type = bool;
        default = true;
        description = ''
          Creates a systemd service and timer to automatically save Vault snapshots.
        '';
      };

      backupCount = mkOption {
        type = addCheck int (x: x >= 0);
        default = null;
        description = ''
          The number of snapshots to keep.  A sensible value matched to the onCalendar
          interval parameter should be used.  Examples of sensible suggestions may be:

            48 backupCount for "hourly" interval (2 days of backups)
            30 backupCount for "daily" interval (1 month of backups)
        '';
      };

      backupDirPrefix = mkOption {
        type = str;
        default = "/var/lib/private/vault/snapshots";
        description = ''
          The top level location to store the snapshots.  The actual storage location
          of the files will be this prefix path with the snapshot job name appended,
          where the job is one of "hourly", "daily" or "custom".

          Therefore, saved snapshot files will be found at:

            $backupDirPrefix/$job/*.snap
        '';
      };

      backupSuffix = mkOption {
        type = addCheck str (x: x != "");
        default = null;
        description = ''
          Sets the saved snapshot filename with a descriptive suffix prior to the file
          extension.  This will enable selective snapshot job pruning.  The form is:

            vault-$(hostname)-$(date +"%Y-%m-%d_%H%M%SZ")-$backupSuffix.snap
        '';
      };

      fixedRandomDelay = mkOption {
        type = bool;
        default = true;
        description = ''
          Makes randomizedDelaySec fixed between service restarts if true.
          This will reduce jitter and allow the interval to remain fixed,
          while still allowing start time randomization to avoid leader overload.
        '';
      };

      includeLeader = mkOption {
        type = bool;
        default = true;
        description = ''
          Whether to include the leader in the servers which will save snapshots.
          This may reduce load on the leader slightly, but by default snapshot
          saves are proxied through the leader anyway.

          Reducing leader load from snapshots may be best done by fixed time
          snapshot randomization so snapshot concurrency remains 1.
        '';
      };

      includeReplica = mkOption {
        type = bool;
        default = true;
        description = ''
          Whether to include the replicas in the servers which will save snapshots.

          Reducing leader load from snapshots may be best done by fixed time
          snapshot randomization so snapshot concurrency remains 1.
        '';
      };

      interval = mkOption {
        type = addCheck str (x: x != "");
        default = null;
        description = ''
          The default onCalendar systemd timer string to trigger snapshot backups.
          Any valid systemd OnCalendar string may be used here.  Sensible
          defaults for backupCount and randomizedDelaySec should match this parameter.
          Examples of sensible suggestions may be:

            hourly: 3600 randomizedDelaySec, 48 backupCount (2 days)
            daily:  86400 randomizedDelaySec, 30 backupCount (1 month)
        '';
      };

      randomizedDelaySec = mkOption {
        type = addCheck int (x: x >= 0);
        default = 0;
        description = ''
          A randomization period to be added to each systemd timer to avoid
          leader overload.  By default fixedRandomDelay will also be true to minimize
          jitter and maintain fixed interval snapshots.  Sensible defaults for
          backupCount and randomizedDelaySec should match this parameter.
          Examples of sensible suggestions may be:

            3600  randomizedDelaySec for "hourly" interval (1 hr randomization)
            86400 randomizedDelaySec for "daily" interval (1 day randomization)
        '';
      };

      owner = mkOption {
        type = str;
        default = "vault:vault";
        description = ''
          The user and group to own the snapshot storage directory and snapshot files.
        '';
      };

      vaultAddress = mkOption {
        type = str;
        default = "https://127.0.0.1:8200";
        description = ''
          The local vault server address, including protocol and port.
        '';
      };
    };
  };

  snapshotTimer = job: {
    partOf = ["vault-snapshots-${job}.service"];
    timerConfig = {
      OnCalendar = cfg.${job}.interval;
      RandomizedDelaySec = cfg.${job}.randomizedDelaySec;
      FixedRandomDelay = cfg.${job}.fixedRandomDelay;
      AccuracySec = "1us";
    };
    wantedBy = ["timers.target"];
  };

  snapshotService = job: {
    environment = {
      OWNER = cfg.${job}.owner;
      BACKUP_DIR = "${cfg.${job}.backupDirPrefix}/${job}";
      BACKUP_SUFFIX = "-${cfg.${job}.backupSuffix}";
      INCLUDE_LEADER = boolToString cfg.${job}.includeLeader;
      INCLUDE_REPLICA = boolToString cfg.${job}.includeReplica;
      VAULT_ADDR = cfg.${job}.vaultAddress;
      VAULT_FORMAT = "json";
    };

    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "30s";
      ExecStart = let
        name = "vault-snapshot-${job}-script.sh";
        script = pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = with pkgs; [coreutils hostname jq nushell vault-bin];
          text = ''
            set -x

            SNAP_NAME="$BACKUP_DIR/vault-$(hostname)-$(date +"%Y-%m-%d_%H%M%SZ''${BACKUP_SUFFIX}").snap"

            applyPerms () {
              TARGET="$1"
              PERMS="$2"

              chown "$OWNER" "$TARGET"
              chmod "$PERMS" "$TARGET"
            }

            takeVaultSnapshot () {
              if [ ! -d "$BACKUP_DIR" ]; then
                mkdir -p "$BACKUP_DIR"
                applyPerms "$BACKUP_DIR" 0700
              fi
              vault operator raft snapshot save "$SNAP_NAME"
              applyPerms "$SNAP_NAME" 0400
            }

            set +x
            VAULT_TOKEN="$(< ${hashiTokens.vault})"
            export VAULT_TOKEN
            set -x

            STATUS="$(vault status)"

            if jq -e '.storage_type != "raft"' <<< "$STATUS"; then
              echo "Vault storage backend is not raft."
              echo "Ensure the appropriate storage backend is being snapshotted."
              exit 0
            fi

            if jq -e '(.is_self // false) == true' <<< "$STATUS"; then
              ROLE="leader"
            else
              ROLE="replica"
            fi

            if [ "$ROLE" = "leader" ] && [ "$INCLUDE_LEADER" = "true" ]; then
              takeVaultSnapshot
            elif [ "$ROLE" = "replica" ] && [ "$INCLUDE_REPLICA" = "true" ]; then
              takeVaultSnapshot
            fi

            # shellcheck disable=SC2016
            nu -c '
              ls $"($env.BACKUP_DIR)"
              | where name =~ $"($env.BACKUP_SUFFIX).snap$"
              | where type == file
              | sort-by modified
              | drop ${toString cfg.${job}.backupCount}
              | each {|f| rm $"($f.name)" | echo $"Deleted: ($f.name)"}
            '
          '';
        };
      in "${script}/bin/${name}";
    };
  };
in {
  options = {
    services.vault-snapshots = {
      enable = mkEnableOption ''
        Enable Vault snapshots.

        By default hourly snapshots will be taken and stored for 2 days on each vault server.
        Modify services.vault-snapshots.hourly options to customize or disable.

        By default daily snapshots will be taken and stored for 1 month on each vault server.
        Modify services.vault-snapshots.daily options to customize or disable.

        By default customized snapshots are disabled.
        Modify services.vault-snapshots.custom options to enable and customize.
      '';

      defaultHourlyOpts = mkOption {
        type = attrs;
        internal = true;
        default = {
          enable = true;
          backupCount = 48;
          backupSuffix = "hourly";
          interval = "hourly";
          randomizedDelaySec = 3600;
        };
      };

      defaultDailyOpts = mkOption {
        type = attrs;
        internal = true;
        default = {
          enable = true;
          backupCount = 30;
          backupSuffix = "daily";
          interval = "daily";
          randomizedDelaySec = 86400;
        };
      };

      hourly = mkOption {
        type = snapshotJobConfig;
        default = cfg.defaultHourlyOpts;
      };

      daily = mkOption {
        type = snapshotJobConfig;
        default = cfg.defaultDailyOpts;
      };

      custom = mkOption {
        type = snapshotJobConfig;
        default = {
          enable = false;
          backupSuffix = "custom";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Hourly snapshot configuration
    systemd.timers.vault-snapshots-hourly =
      mkIf cfg.hourly.enable (snapshotTimer "hourly");
    systemd.services.vault-snapshots-hourly =
      mkIf cfg.hourly.enable (snapshotService "hourly");

    # Daily snapshot configuration
    systemd.timers.vault-snapshots-daily =
      mkIf cfg.daily.enable (snapshotTimer "daily");
    systemd.services.vault-snapshots-daily =
      mkIf cfg.daily.enable (snapshotService "daily");

    # Custom snapshot configuration
    systemd.timers.vault-snapshots-custom =
      mkIf cfg.custom.enable (snapshotTimer "custom");
    systemd.services.vault-snapshots-custom =
      mkIf cfg.custom.enable (snapshotService "custom");
  };
}
