{
  config,
  lib,
  pkgs,
  ...
}: {
  # Workaround to address broken lo interface in Nomad created net namespaces
  # https://github.com/hashicorp/nomad/issues/10014
  systemd.services.monitor-exec-driver-lo = {
    path = with pkgs; [coreutils inotify-tools iproute2 gnugrep];
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStart = pkgs.writeBashChecked "monitor-exec-driver-lo" ''
        set -euo pipefail

        mkdir -p /var/run/netns

        # Run upon detection of any create or modify network namespace changes
        inotifywait -m -e create -e modify --format '%w%f' /var/run/netns | \
          while read -r NS_CHANGED; do
            NS="$(basename "$NS_CHANGED" /var/run/netns)"
            echo "Namespace change detected: $NS_CHANGED"

            echo "Namespace loopback state before fixup:"
            ip netns exec "$NS" ip -br a || : | grep -E '^lo.*$' || :

            # All Nomad namespaces should have an operational loopback interface
            ip netns exec "$NS" ip link set lo up || :

            echo "Namespace loopback state after fixup:"
            ip netns exec "$NS" ip -br a || : | grep -E '^lo.*$' || :
          done
      '';
    };
  };
}
