{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkEnableOption mkOption types;
  inherit (types) addCheck bool int str;

  cfg = config.services.consul-snapshots;

in {
  options = {
    services.consul-snapshots = {
      enable = mkEnableOption "Consul snapshots";

      fixedRandomDelay = mkOption {
        type = bool;
        default = true;
        description = ''
          Makes randomizedDelaySec fixed between service restarts if true.
          This will reduce jitter and allow the interval to remain fixed,
          while still allowing start time randomization to avoid leader overload.
        '';
      };

      randomizedDelaySec = mkOption {
        type = addCheck int (x: x >= 0);
        default = if cfg.interval == "hourly" then
          3600
        else if cfg.interval == "daily" then
          86400
        else
          0;
        description = ''
          A randomization period to be added to each systemd timer to avoid
          leader overload.  By default fixedRandomDelay will also be true to minimize
          jitter and maintain fixed interval snapshots.  The defaults relate to
          the onCalendar interval parameter in the following manner:

            3600  randomizedDelaySec for "hourly" interval (1 hr randomization)
            86400 randomizedDelaySec for "daily" interval (1 day randomization)
            0     randomizedDelaySec for any other interval
        '';
      };

      backupCount = mkOption {
        type = addCheck int (x: x >= 0);
        default = if cfg.interval == "hourly" then
          168
        else if cfg.interval == "daily" then
          30
        else
          50;
        description = ''
          The number of snapshots to keep.  The defaults relate to the onCalendar
          interval parameter in the following manner:

            168 backupCount for "hourly" interval (1 week of backups)
            30  backupCount for "daily" interval (1 month of backups)
            50  backupCount for any other interval
        '';
      };

      backupDir = mkOption {
        type = str;
        default = "/var/lib/private/consul/snapshots";
        description = ''
          The location to store the snapshots.
        '';
      };

      interval = mkOption {
        default = "hourly";
        description = ''
          The default onCalendar systemd timer string to trigger snapshot backups.
          Any valid systemd OnCalendar string may be used here.  However, sensible
          defaults for backupCount and randomizedDelaySec will only be applied for
          "hourly" and "daily" interval settings.  Other settings will default to
          backupCount of 50 and randomizedDelaySec of 0.  In these cases, both
          backupCount and randomizedDelaySec should be declared to something
          sensible.  For hourly and daily interval settings, the following defaults
          will be used:

            hourly: 3600 randomizedDelaySec, 168 backupCount (1 week)
            daily:  86400 randomizedDelaySec, 30 backupCount (1 month)
        '';
      };

      owner = mkOption {
        type = str;
        default = "consul:consul";
        description = ''
          The user and group to own the snapshot storage directory and snapshot files.
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
    };
  };

  config = mkIf cfg.enable {
    systemd = {
      timers.consul-snapshots = {
        partOf = [ "consul-snapshots.service" ];
        timerConfig = {
          OnCalendar = cfg.interval;
          RandomizedDelaySec = cfg.randomizedDelaySec;
          FixedRandomDelay = cfg.fixedRandomDelay;
        };
        wantedBy = [ "timers.target" ];
      };
      services.consul-snapshots = {
        serviceConfig.Type = "oneshot";
        path = with pkgs; [ consul coreutils findutils gawk hostname ];
        script = builtins.readFile "${(pkgs.writeBashChecked "consul-snapshot-script" ''
          set -exuo pipefail

          OWNER="${cfg.owner}"
          BACKUP_DIR="${cfg.backupDir}"
          INCLUDE_LEADER="${if cfg.includeLeader then "true" else "false"}"
          SNAP_NAME="$BACKUP_DIR/consul-$(hostname)-$(date +"%Y-%m-%d_%H%M%SZ").snap"

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

          isNotLeader () {
            if [ "$(consul info | grep 'leader =' | awk '{print $3}')" = "false" ]; then
              return
            fi
            false
          }

          takeConsulSnapshot () {
            consul snapshot save "$SNAP_NAME"
            applyPerms "$SNAP_NAME" "0400"
          }

          if [ "$INCLUDE_LEADER" = "true" ] || isNotLeader; then
            checkBackupDir
            takeConsulSnapshot
          fi

          find "$BACKUP_DIR" \
            -type f \
            -name "*.snap" \
            -printf "%T@ %p\n" \
            | sort -r -n \
            | tail -n +$((${toString cfg.backupCount} + 1)) \
            | awk '{print $2}' \
            | xargs -r rm
        '')}";
      };
    };
  };
}
