{ config, pkgs, lib, ... }:

let
  cfg = config.services.nomad-snapshots;

  snapshotJobConfig = submodule {
    options = {
      enable = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = ''
          Creates a systemd service and timer to automatically save Nomad snapshots.
        '';
      };

      backupCount = lib.mkOption {
        type = with lib.types; addCheck int (x: x >= 0);
        default = null;
        description = ''
          The number of snapshots to keep.  A sensible value matched to the onCalendar
          interval parameter should be used.  Examples of sensible suggestions may be:

            48 backupCount for "hourly" interval (2 days of backups)
            30 backupCount for "daily" interval (1 month of backups)
        '';
      };

      backupDirPrefix = lib.mkOption {
        type = with lib.types; str;
        default = "/var/lib/private/nomad/snapshots";
        description = ''
          The top level location to store the snapshots.  The actual storage location
          of the files will be this prefix path with the snapshot job name appended,
          where the job is one of "hourly", "daily" or "custom".

          Therefore, saved snapshot files will be found at:

            $backupDirPrefix/$job/*.snap
        '';
      };

      backupSuffix = lib.mkOption {
        type = with lib.types; addCheck str (x: x != "");
        default = null;
        description = ''
          Sets the saved snapshot filename with a descriptive suffix prior to the file
          extension.  This will enable selective snapshot job pruning.  The form is:

            nomad-$(hostname)-$(date +"%Y-%m-%d_%H%M%SZ")-$backupSuffix.snap
        '';
      };

      fixedRandomDelay = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = ''
          Makes randomizedDelaySec fixed between service restarts if true.
          This will reduce jitter and allow the interval to remain fixed,
          while still allowing start time randomization to avoid leader overload.
        '';
      };

      includeLeader = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = ''
          Whether to include the leader in the servers which will save snapshots.
          This may reduce load on the leader slightly, but by default snapshot
          saves are proxied through the leader anyway.

          Reducing leader load from snapshots may be best done by fixed time
          snapshot randomization so snapshot concurrency remains 1.
        '';
      };

      interval = lib.mkOption {
        type = with lib.types; addCheck str (x: x != "");
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

      randomizedDelaySec = lib.mkOption {
        type = with lib.types; addCheck int (x: x >= 0);
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

      owner = lib.mkOption {
        type = with lib.types; str;
        default = "root:root";
        description = ''
          The user and group to own the snapshot storage directory and snapshot files.
        '';
      };

      nomadAddress = lib.mkOption {
        type = with lib.types; str;
        default = "https://127.0.0.1:4646";
        description = ''
          The local nomad server address, including protocol and port.
        '';
      };
    };
  };

  snapshotTimer = job: {
    partOf = [ "nomad-snapshots-${job}.service" ];
    timerConfig = {
      OnCalendar = cfg.${job}.interval;
      RandomizedDelaySec = cfg.${job}.randomizedDelaySec;
      FixedRandomDelay = cfg.${job}.fixedRandomDelay;
      AccuracySec = "1us";
    };
    wantedBy = [ "timers.target" ];
  };

  snapshotService = job: {
    path = with pkgs; [ coreutils curl findutils gawk hostname jq nomad ];

    environment = {
      OWNER = cfg.${job}.owner;
      BACKUP_DIR = "${cfg.${job}.backupDirPrefix}/${job}";
      BACKUP_SUFFIX = "-${cfg.${job}.backupSuffix}";
      INCLUDE_LEADER = lib.boolToString cfg.${job}.includeLeader;
      NOMAD_ADDR = cfg.${job}.nomadAddress;
    };

    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "30s";
      ExecStart = pkgs.writeBashChecked "nomad-snapshot-${job}-script" ''
        set -exuo pipefail

        SNAP_NAME="$BACKUP_DIR/nomad-$(hostname)-$(date +"%Y-%m-%d_%H%M%SZ''${BACKUP_SUFFIX}").snap"

        applyPerms () {
          TARGET="$1"
          PERMS="$2"

          chown "$OWNER" "$TARGET"
          chmod "$PERMS" "$TARGET"
        }

        checkBackupDir () {
          if [ ! -d "$BACKUP_DIR" ]; then
            mkdir -p "$BACKUP_DIR"
            applyPerms "$BACKUP_DIR" "0700"
          fi
        }

        exportToken () {
          if [ ! -f /run/keys/nomad-snapshot-token ]; then
            echo "Suitable nomad token for snapshotting not found."
            echo "Ensure the appropriate token for snapshotting is available.";
            exit 0;
          else
            set +x
            NOMAD_TOKEN="$(< /run/keys/nomad-snapshot-token)"
            export NOMAD_TOKEN
            set -x
          fi
        }

        isNotLeader () {
          [ "$INCLUDE_LEADER" = "true" ] || \
            nomad agent-info --json | jq -e '.stats.nomad.leader == "false"'
        }

        takeNomadSnapshot () {
          nomad operator snapshot save "$SNAP_NAME"
          applyPerms "$SNAP_NAME" "0400"
        }

        export NOMAD_ADDR
        exportToken

        if isNotLeader; then
          checkBackupDir
          takeNomadSnapshot
        fi

        find "$BACKUP_DIR" \
          -type f \
          -name "*''${BACKUP_SUFFIX}.snap" \
          -printf "%T@ %p\n" \
          | sort -r -n \
          | tail -n +${toString (cfg.${job}.backupCount + 1)} \
          | awk '{print $2}' \
          | xargs -r rm
      '';
    };
  };

in {
  options = {
    services.nomad-snapshots = {
      enable = lib.mkEnableOption ''
        Enable Nomad snapshots.

        By default hourly snapshots will be taken and stored for 2 days on each nomad server.
        Modify services.nomad-snapshots.hourly options to customize or disable.

        By default daily snapshots will be taken and stored for 1 month on each nomad server.
        Modify services.nomad-snapshots.daily options to customize or disable.

        By default customized snapshots are disabled.
        Modify services.nomad-snapshots.custom options to enable and customize.
      '';

      hourly = lib.mkOption {
        type = with lib.types; snapshotJobConfig;
        default = {
          enable = true;
          backupCount = 48;
          backupSuffix = "hourly";
          interval = "hourly";
          randomizedDelaySec = 3600;
        };
      };

      daily = lib.mkOption {
        type = with lib.types; snapshotJobConfig;
        default = {
          enable = true;
          backupCount = 30;
          backupSuffix = "daily";
          interval = "daily";
          randomizedDelaySec = 86400;
        };
      };

      custom = lib.mkOption {
        type = with lib.types; snapshotJobConfig;
        default = {
          enable = false;
          backupSuffix = "custom";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Hourly snapshot configuration
    systemd.timers.nomad-snapshots-hourly =
      lib.mkIf cfg.hourly.enable (snapshotTimer "hourly");
    systemd.services.nomad-snapshots-hourly =
      lib.mkIf cfg.hourly.enable (snapshotService "hourly");

    # Daily snapshot configuration
    systemd.timers.nomad-snapshots-daily =
      lib.mkIf cfg.daily.enable (snapshotTimer "daily");
    systemd.services.nomad-snapshots-daily =
      lib.mkIf cfg.daily.enable (snapshotService "daily");

    # Custom snapshot configuration
    systemd.timers.nomad-snapshots-custom =
      lib.mkIf cfg.custom.enable (snapshotTimer "custom");
    systemd.services.nomad-snapshots-custom =
      lib.mkIf cfg.custom.enable (snapshotService "custom");
  };
}
