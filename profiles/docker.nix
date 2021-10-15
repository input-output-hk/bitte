{ lib, ... }: {
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "daily";
    };

    extraOptions = lib.concatStringsSep " " [
      "--log-driver=journald"
      # For simplicity, let the bridge network have a static ip/mask (by default it
      # would choose this one, but fall back to the next range if this one is already used)
      "--bip=172.17.0.1/16"
      # Which allows us to specify that containers should use the local host as the DNS server
      # This is written into the containers /etc/resolv.conf
      "--dns=172.17.0.1"
    ];
  };

  # needed to access AWS meta-data after docker starts veth* devices.
  networking.interfaces.ens5.ipv4.routes = [{
    address = "169.254.169.252";
    prefixLength = 30;
  }];

  # Workaround dhcpcd breaking AWS meta-data, resulting in vault-agent failure.
  # Ref: https://github.com/NixOS/nixpkgs/issues/109389
  # Rather than explicitly deny all veth* interfaces access to dhcpcd,
  # ensure the meta-data route is added upon service restart.
  networking.dhcpcd.runHook = ''
    if [ "$reason" = BOUND -o "$reason" = REBOOT ]; then
      /run/current-system/systemd/bin/systemctl try-reload-or-restart network-addresses-ens5.service || true
    fi
  '';

  # Allow docker containers to issue DNS queries to the local host, which runs dnsmasq,
  # which allows them to resolve consul service domains as described in https://www.consul.io/docs/discovery/dns
  networking.firewall.extraCommands = ''
    iptables -A INPUT -i docker0 -p udp -m udp --dport 53 -j ACCEPT
  '';
}
