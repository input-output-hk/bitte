{ pkgs, ... }: let
  # Maximum ZFS ARC max size based on percentage:
  zfs_arc_max_percent = 10;
in {

  # In some situations custom tuning of ZFS ARC cache may be required.
  # ZFS ARC will by default consume 50% of available RAM as cache.
  # ARC will shrink dynamically under memory pressure, but in practice,
  # if RAM demands of the system expand quickly, ARC may not shrink
  # fast enough to avoid OOM as was often observed on CI machines with ZFS.
  # The following parameter can be adjusted if needed.
  #
  # Refs:
  #   https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Module%20Parameters.html?highlight=arc_max#zfs-arc-max
  #   https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Module%20Parameters.html?highlight=arc_max#zfs-arc-min
  #
  # Fixed value ZFS ARC max:
  #
  # boot.kernelParams = [
  #   "zfs.zfs_arc_max=${toString (1024*1024*1024*10)}"
  # ];
  #
  # Fixed percentage ZFS ARC max
  # * See ZFS ARC max percentage parameter above and systemd timer/script below.
  # * If the percentage results in a lower byte value than ZFS ARC min, the min will be the floor

  services.zfs = {
    autoSnapshot = {
      enable = true;
      monthly = 1;
    };
    autoScrub.enable = true;
    trim.enable = true;
  };

  systemd = {
    timers = {
      zfs-arc-max-percent-enable = {
        wantedBy = [ "timers.target" ];
        partOf = [ "zfs-arc-max-percent-enable.service" ];
        timerConfig.OnCalendar = "hourly";
      };

      zfs-snapshot-enable = {
        wantedBy = [ "timers.target" ];
        partOf = [ "zfs-snapshot-enable.service" ];
        timerConfig.OnCalendar = "daily";
      };
    };

    services = {
      zfs-arc-max-percent-enable = {
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
          RAM_ZFS_ARC_MAX_PERCENT="${toString zfs_arc_max_percent}"
          echo "ZFS ARC max percentage target: ''${RAM_ZFS_ARC_MAX_PERCENT}%"
          RAM_ZFS_ARC_MAX_BYTES="$((RAM_TOTAL_BYTES * RAM_ZFS_ARC_MAX_PERCENT / 100))"
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
    };
  };
}
