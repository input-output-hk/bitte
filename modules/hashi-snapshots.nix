{
  config,
  pkgs,
  lib,
  hashiTokens,
  ...
}: let
  cfg = config.services.hashi-snapshots;

  inherit (lib) boolToString listToAttrs mkEnableOption mkIf mkMerge mkOption nameValuePair toUpper;
  inherit (lib.types) attrs bool enum int ints nonEmptyStr str submodule;

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
        type = ints.unsigned;
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
        default = null;
        description = ''
          The top level location to store the snapshots.  The actual storage location
          of the files will be this prefix path with the snapshot job name appended,
          where the job is one of "hourly", "daily" or "custom".

          Therefore, saved snapshot files will be found at:

            $backupDirPrefix/$job/*.snap
        '';
      };

      backupSuffix = mkOption {
        type = nonEmptyStr;
        default = null;
        description = ''
          Sets the saved snapshot filename with a descriptive suffix prior to the file
          extension.  This will enable selective snapshot job pruning.  The form is:

            $HASHI_SERVICE-$(hostname)-$(date +"%Y-%m-%d_%H%M%SZ")-$backupSuffix.snap
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

      hashiAddress = mkOption {
        type = str;
        default = null;
        description = ''
          The local Hashicorp service server address, including protocol and port.
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
        type = nonEmptyStr;
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
        type = ints.unsigned;
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
        default = null;
        description = ''
          The user and group to own the snapshot storage directory and snapshot files.
        '';
      };
    };
  };

  snapshotTimer = hashiService: job: {
    partOf = ["${hashiService}-snapshots-${job}.service"];
    timerConfig = {
      OnCalendar = cfg.${hashiService}.${job}.interval;
      RandomizedDelaySec = cfg.${hashiService}.${job}.randomizedDelaySec;
      FixedRandomDelay = cfg.${hashiService}.${job}.fixedRandomDelay;
      AccuracySec = "1us";
    };
    wantedBy = ["timers.target"];
  };

  snapshotService = hashiService: job: {
    environment = {
      OWNER = cfg.${hashiService}.${job}.owner;
      BACKUP_DIR = "${cfg.${hashiService}.${job}.backupDirPrefix}/${job}";
      BACKUP_SUFFIX = "-${cfg.${hashiService}.${job}.backupSuffix}";
      HASHI_SERVICE = hashiService;
      INCLUDE_LEADER = boolToString cfg.${hashiService}.${job}.includeLeader;
      INCLUDE_REPLICA = boolToString cfg.${hashiService}.${job}.includeReplica;
      "${toUpper hashiService}_ADDR" = mkIf (hashiService != "consul") cfg.${hashiService}.${job}.hashiAddress;
      "${toUpper hashiService}_HTTP_ADDR" = mkIf (hashiService == "consul") cfg.${hashiService}.${job}.hashiAddress;
      "${toUpper hashiService}_FORMAT" = mkIf (hashiService == "vault") "json";
    };

    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "30s";
      ExecStart = let
        name = "${hashiService}-snapshot-${job}-script.sh";
        script = snapshotScripts.${hashiService} job;
      in "${script}/bin/${name}";
    };
  };

  snapshotScripts = let
    mkSnapshotScript = {
      hashiService,
      job,
      extraInputs,
      snapshotCmd,
      envPrep,
      roleCmd,
    }:
      pkgs.writeShellApplication {
        name = "${hashiService}-snapshot-${job}-script.sh";
        runtimeInputs = with pkgs; [coreutils hostname nushell] ++ extraInputs;
        text = ''
          set -x

          SNAP_NAME="$BACKUP_DIR/$HASHI_SERVICE-$(hostname)-$(date +"%Y-%m-%d_%H%M%SZ$BACKUP_SUFFIX").snap"

          applyPerms () {
            TARGET="$1"
            PERMS="$2"

            chown "$OWNER" "$TARGET"
            chmod "$PERMS" "$TARGET"
          }

          fsPrep () {
            if [ ! -d "$BACKUP_DIR" ]; then
              mkdir -p "$BACKUP_DIR"
              applyPerms "$BACKUP_DIR" "0700"
            fi
          }

          takeSnapshot () {
            ${snapshotCmd}
            applyPerms "$SNAP_NAME" "0400"
          }

          fsPrep

          ${envPrep}

          if ${roleCmd}; then
            ROLE="leader"
          else
            ROLE="replica"
          fi

          if [ "$ROLE" = "leader" ] && [ "$INCLUDE_LEADER" = "true" ]; then
            takeSnapshot
          elif [ "$ROLE" = "replica" ] && [ "$INCLUDE_REPLICA" = "true" ]; then
            takeSnapshot
          fi

          # shellcheck disable=SC2016
          nu -c '
            ls $"($env.BACKUP_DIR)"
            | where name =~ $"($env.BACKUP_SUFFIX).snap$"
            | where type == file
            | sort-by modified
            | drop ${toString cfg.${hashiService}.${job}.backupCount}
            | each {|f| rm $"($f.name)"; echo $"Deleted: ($f.name)"}
          ' || true
        '';
      };
  in {
    consul = job:
      mkSnapshotScript {
        inherit job;
        hashiService = "consul";
        extraInputs = with pkgs; [consul gnugrep];
        snapshotCmd = ''consul snapshot save "$SNAP_NAME"'';
        envPrep = "";
        roleCmd = "consul info | grep -E '^\\s*leader\\s+=\\s+true$'";
      };

    nomad = job:
      mkSnapshotScript {
        inherit job;
        hashiService = "nomad";
        extraInputs = with pkgs; [jq nomad];
        snapshotCmd = ''nomad operator snapshot save "$SNAP_NAME"'';
        envPrep = ''
          set +x
          NOMAD_TOKEN=$(< ${hashiTokens.nomad-snapshot})
          export NOMAD_TOKEN
          set -x

          STATUS=$(nomad agent-info --json)
        '';
        roleCmd = ''jq -e '(.stats.nomad.leader // "false") == "true"' <<< "$STATUS"'';
      };

    vault = job:
      mkSnapshotScript {
        inherit job;
        hashiService = "vault";
        extraInputs = with pkgs; [jq vault-bin];
        snapshotCmd = ''vault operator raft snapshot save "$SNAP_NAME"'';
        envPrep = ''
          set +x
          VAULT_TOKEN=$(< ${hashiTokens.vault})
          export VAULT_TOKEN
          set -x

          STATUS=$(vault status)

          if jq -e '.storage_type != "raft"' <<< "$STATUS"; then
            echo "Vault storage backend is not raft."
            echo "Ensure the appropriate storage backend is being snapshotted."
            exit 0
          fi
        '';
        roleCmd = ''jq -e '(.is_self // false) == true' <<< "$STATUS"'';
      };
  };
in {
  options = let
    snapshotDescription = hashiService: ''
      By default hourly snapshots will be taken and stored for 2 days on each snapshotted server.
      Modify services.hashi-snapshots.${hashiService}.hourly options to customize or disable.

      By default daily snapshots will be taken and stored for 1 month on each snapshotted server.
      Modify services.hashi-snapshots.${hashiService}.daily options to customize or disable.

      By default customized snapshots are disabled.
      Modify services.hashi-snapshots.${hashiService}.custom options to enable and customize.
    '';
  in {
    services.hashi-snapshots =
      {
        enableConsul = mkEnableOption ''
          Enable Consul snapshots.
          ${snapshotDescription "consul"}
        '';

        enableNomad = mkEnableOption ''
          Enable Nomad snapshots.
          ${snapshotDescription "nomad"}
        '';

        enableVault = mkEnableOption ''
          Enable Vault snapshots.
          ${snapshotDescription "vault"}
        '';

        defaultHashiOpts = mkOption {
          type = attrs;
          internal = true;
          default = {
            consul = {
              backupDirPrefix = "/var/lib/private/consul/snapshots";
              hashiAddress = "http://127.0.0.1:8500";
              owner = "consul:consul";
            };
            nomad = {
              backupDirPrefix = "/var/lib/private/nomad/snapshots";
              hashiAddress = "https://127.0.0.1:4646";
              owner = "root:root";
            };
            vault = {
              backupDirPrefix = "/var/lib/private/vault/snapshots";
              hashiAddress = "https://127.0.0.1:8200";
              owner = "vault:vault";
            };
          };
        };

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
      }
      // (
        listToAttrs
        (map
          (
            hashiService:
              nameValuePair
              hashiService
              {
                hourly = mkOption {
                  type = snapshotJobConfig;
                  default = cfg.defaultHourlyOpts // cfg.defaultHashiOpts.${hashiService};
                };

                daily = mkOption {
                  type = snapshotJobConfig;
                  default = cfg.defaultDailyOpts // cfg.defaultHashiOpts.${hashiService};
                };

                custom = mkOption {
                  type = snapshotJobConfig;
                  default =
                    {
                      enable = false;
                      backupSuffix = "custom";
                    }
                    // cfg.defaultHashiOpts.${hashiService};
                };
              }
          )
          ["consul" "nomad" "vault"])
      );
  };

  config = let
    mkSnapshotJobSet = hashiService: job: {
      systemd.timers."${hashiService}-snapshots-${job}" =
        mkIf cfg.${hashiService}.${job}.enable (snapshotTimer hashiService job);

      systemd.services."${hashiService}-snapshots-${job}" =
        mkIf cfg.${hashiService}.${job}.enable (snapshotService hashiService job);
    };

    mkSnapshotServices = hashiService:
      mkMerge [
        (mkSnapshotJobSet hashiService "hourly")
        (mkSnapshotJobSet hashiService "daily")
        (mkSnapshotJobSet hashiService "custom")
      ];
  in
    mkMerge [
      (mkIf cfg.enableConsul (mkSnapshotServices "consul"))
      (mkIf cfg.enableNomad (mkSnapshotServices "nomad"))
      (mkIf cfg.enableVault (mkSnapshotServices "vault"))
    ];
}
