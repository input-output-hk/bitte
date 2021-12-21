{ lib, pkgs, config, ... }:

let cfg = config.services.zfs-client-options;

in {
  options = {
    services.zfs-client-options = {
      enable = lib.mkEnableOption "Client ZFS options";

      arcMaxMiB = lib.mkOption {
        type = with lib.types; addCheck int (x: x >= 0);
        default = 1024;
        description = ''
          The maximum ZFS ARC max size based on absolute MiB.
          See additional information in the enableZfsArcMaxControl option description.

          Note that this option will utilize a timed systemd service, the same
          as the arcMaxPercent option does, rather than a `boot.kernelParams`
          option so that a reboot is not required to take effect.
        '';
      };

      arcMaxPercent = lib.mkOption {
        type = with lib.types; addCheck int (x: x >= 0 && x <= 100);
        default = 10;
        description = ''
          The maximum ZFS ARC max size based on total RAM percentage.
          See additional information in the enableZfsArcMaxControl option description.
        '';
      };

      enableZfsArcMaxControl = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = ''
          Enable client ZFS ARC max control.

          In some situations custom tuning of ZFS ARC cache may be required.
          ZFS ARC will by default consume 50% of available RAM as cache.
          ARC will shrink dynamically under memory pressure, but in practice,
          if RAM demands of the system expand quickly, ARC may not shrink
          fast enough to avoid OOM as was often observed on CI machines with ZFS.

          By specifying either a fixed percentage or static ZFS ARC max results
          in a lower byte value than ZFS ARC min, the min will be the floor.

          Refs:
            https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Module%20Parameters.html?highlight=arc_max#zfs-arc-max
            https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Module%20Parameters.html?highlight=arc_max#zfs-arc-min
        '';
      };

      enableZfsScrub = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = "Enable client ZFS scrubbing";
      };

      enableZfsSnapshots = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = "Enable client ZFS snapshots";
      };

      enableZfsTrim = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = "Enable client ZFS trimming";
      };

      useArcMaxPercent = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        description = ''
          Utilize the arcMaxPercent option in preference over the
          arcMaxMiB option if true.  Otherwise, utilize arcMaxMiB
          if false.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.zfs = {
      autoSnapshot.enable = lib.mkIf cfg.enableZfsSnapshots true;
      autoSnapshot.monthly = 1;
      autoScrub.enable = lib.mkIf cfg.enableZfsScrub true;
      trim.enable = lib.mkIf cfg.enableZfsTrim true;
    };

    systemd = {
      timers = {
        zfs-arc-max-control-enable = lib.mkIf cfg.enableZfsArcMaxControl {
          wantedBy = [ "timers.target" ];
          partOf = [ "zfs-arc-max-control-enable.service" ];
          timerConfig.OnCalendar = "hourly";
        };

        zfs-snapshot-enable = lib.mkIf cfg.enableZfsSnapshots {
          wantedBy = [ "timers.target" ];
          partOf = [ "zfs-snapshot-enable.service" ];
          timerConfig.OnCalendar = "daily";
        };
      };

      services = {
        zfs-arc-max-control-enable = lib.mkIf cfg.enableZfsArcMaxControl {
          serviceConfig.Type = "oneshot";
          path = with pkgs; [ gawk gnugrep zfs ];
          script = ''
            set -euo pipefail
            echo " "
            echo "ZFS arcstats prior to adjustments:"
            grep -E '^c |^c_min|^c_max|^size' /proc/spl/kstat/zfs/arcstats
            arcstat
            echo " "
            echo "ZFS arcstat adjustments:"
            # Get total memory:
            # meminfo shows kB for total ram, but is actually KiB:
            # Refs:
            #   https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/deployment_guide/s2-proc-meminfo
            #   https://lore.kernel.org/patchwork/patch/666444/
            RAM_TOTAL_BYTES="$(($(grep -E '^MemTotal' /proc/meminfo | awk '{ print $2 }') * 1024))"
            echo "Total RAM bytes available: $RAM_TOTAL_BYTES"

            USE_ARC_MAX_PERCENT="${
              if cfg.useArcMaxPercent then "true" else "false"
            }"

            if [ "$USE_ARC_MAX_PERCENT" = "true" ]; then
              RAM_ZFS_ARC_MAX_PERCENT="${toString cfg.arcMaxPercent}"
              echo "ZFS ARC max percentage target specified: ''${RAM_ZFS_ARC_MAX_PERCENT}%"
              RAM_ZFS_ARC_MAX_BYTES="$((RAM_TOTAL_BYTES * RAM_ZFS_ARC_MAX_PERCENT / 100))"
            else
              RAM_ZFS_ARC_MAX_STATIC="${toString cfg.arcMaxMiB}"
              echo "ZFS ARC max static target specified: $RAM_ZFS_ARC_MAX_STATIC MiB"
              RAM_ZFS_ARC_MAX_BYTES="$((RAM_ZFS_ARC_MAX_STATIC * 1024 * 1024))"
            fi

            echo "ZFS ARC total target bytes: $RAM_ZFS_ARC_MAX_BYTES"
            if [ -r "/proc/spl/kstat/zfs/arcstats" ]; then
              RAM_ZFS_ARC_MAX_CURRENT_BYTES="$(grep -E '^c_max' /proc/spl/kstat/zfs/arcstats | awk '{ print $3 }')"
              RAM_ZFS_ARC_MIN_CURRENT_BYTES="$(grep -E '^c_min' /proc/spl/kstat/zfs/arcstats | awk '{ print $3 }')"
              RAM_ZFS_ARC_SIZE_CURRENT_BYTES="$(grep -E '^size' /proc/spl/kstat/zfs/arcstats | awk '{ print $3 }')"
              RAM_ZFS_ARC_MIN_MATCH_BYTES=$((RAM_ZFS_ARC_MIN_CURRENT_BYTES + 1))
            else
              echo "Unable to process ZFS arcstats proc file: /proc/spl/kstat/zfs/arcstats"
              echo " "
              exit 1
            fi
            if [ "$RAM_ZFS_ARC_MAX_BYTES" -lt "$RAM_ZFS_ARC_MIN_MATCH_BYTES" ]; then
              RAM_ZFS_ARC_EFFECTIVE_MAX_BYTES="$RAM_ZFS_ARC_MIN_MATCH_BYTES"
              echo "ZFS ARC MAX is less then ZFS ARC MIN; effective ARC MAX will be ARC MIN bytes plus 1: $RAM_ZFS_ARC_MIN_MATCH_BYTES"
            else
              RAM_ZFS_ARC_EFFECTIVE_MAX_BYTES="$RAM_ZFS_ARC_MAX_BYTES"
            fi
            echo "ZFS ARC MAX current size: $RAM_ZFS_ARC_MAX_CURRENT_BYTES"
            if [ "$RAM_ZFS_ARC_MAX_CURRENT_BYTES" -ne "$RAM_ZFS_ARC_EFFECTIVE_MAX_BYTES" ]; then
              echo "Setting ZFS ARC MAX byte size: $RAM_ZFS_ARC_EFFECTIVE_MAX_BYTES"
              echo "$RAM_ZFS_ARC_EFFECTIVE_MAX_BYTES" > /sys/module/zfs/parameters/zfs_arc_max
            else
              echo "ZFS ARC MAX size is already at target bytes: $RAM_ZFS_ARC_EFFECTIVE_MAX_BYTES"
            fi
            echo "ZFS ARC current byte size: $RAM_ZFS_ARC_SIZE_CURRENT_BYTES"
            if [ "$RAM_ZFS_ARC_SIZE_CURRENT_BYTES" -gt "$RAM_ZFS_ARC_EFFECTIVE_MAX_BYTES" ]; then
              echo "Clearing ZFS ARC cache to enforce ARC max effective target: $RAM_ZFS_ARC_EFFECTIVE_MAX_BYTES"
              echo 3 > /proc/sys/vm/drop_caches
            else
              echo "ZFS ARC cache size is already at target effective max bytes or less: $RAM_ZFS_ARC_SIZE_CURRENT_BYTES"
            fi
            echo " "
            echo "ZFS arcstat post adjustments:"
            grep -E '^c |^c_min|^c_max|^size' /proc/spl/kstat/zfs/arcstats
            arcstat
            echo " "
          '';
        };

        zfs-snapshot-enable = lib.mkIf cfg.enableZfsSnapshots {
          serviceConfig.Type = "oneshot";
          path = [ pkgs.zfs ];
          script = ''
            set -euo pipefail
            echo "The current state of zfs autosnapshots is:"
            zfs get com.sun:auto-snapshot
            echo " "
            zfs set com.sun:auto-snapshot=true tank
            echo "The new state of zfs autosnapshots is:"
            zfs get com.sun:auto-snapshot
            echo " "
            echo "The current size of existing zfs snapshots is:"
            zfs list -o space -t filesystem,snapshot
            echo " "
          '';
        };
      };
    };
  };
}
