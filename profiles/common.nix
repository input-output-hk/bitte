{ config, lib, ... }: {
  imports = [
    ./consul/default.nix
    ./nix.nix
    ./promtail.nix
    ./slim.nix
    ./ssh.nix
    ./vault/default.nix
  ];

  services = {
    amazon-ssm-agent.enable = true;
    vault.enable = true;
    consul.enable = true;
    openntpd.enable = true;
    fail2ban.enable = true;
  };

  environment.variables = { AWS_DEFAULT_REGION = config.cluster.region; };

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = false;
  networking.timeServers = lib.mkForce [
    "0.nixos.pool.ntp.org"
    "1.nixos.pool.ntp.org"
    "2.nixos.pool.ntp.org"
    "3.nixos.pool.ntp.org"
  ];
  boot.cleanTmpDir = true;

  networking.firewall = let
    all = {
      from = 0;
      to = 65535;
    };
  in {
    enable = true;
    allowPing = true;
    allowedTCPPortRanges = [ all ];
    allowedUDPPortRanges = [ all ];
  };

  time.timeZone = "UTC";
}
