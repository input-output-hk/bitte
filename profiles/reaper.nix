{ pkgs, ... }: {
  systemd.services.reaper = {
    description = "kill orphaned nomad tasks";
    wantedBy = [ "nomad.service" ];
    path = with pkgs; [ coreutils procps gawk ];
    script = ''
      set -euo pipefail
      while true; do
        for pid in $(ps -eo 'ppid= uid= pid=' | egrep '^\s*1 65534' | awk '{ print $3 }'); do
          echo "killing $pid"
          ps "$pid"
          kill "$pid"
        done
        sleep 60
      done
    '';
  };
}
