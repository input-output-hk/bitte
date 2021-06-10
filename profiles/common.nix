{ config, lib, self, nodeName, ... }: {
  imports = [
    ../modules
    ./consul/default.nix
    ./consul/policies.nix
    ./nix.nix
    ./promtail.nix
    ./slim.nix
    ./ssh.nix
    ./vault/default.nix
  ];

  services = {
    ssm-agent.enable = lib.mkDefault true;
    vault.enable = lib.mkDefault true;
    consul.enable = lib.mkDefault true;
  };

  environment.variables = { AWS_DEFAULT_REGION = config.cluster.region; };

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = lib.mkDefault false;
  services.openntpd.enable = lib.mkDefault true;
  networking.hostName = nodeName;
  networking.timeServers = lib.mkForce [
    "0.nixos.pool.ntp.org"
    "1.nixos.pool.ntp.org"
    "2.nixos.pool.ntp.org"
    "3.nixos.pool.ntp.org"
  ];
  boot.cleanTmpDir = true;
  networking.firewall.allowPing = lib.mkDefault true;
  # TODO: enable again
  networking.firewall.enable = lib.mkDefault false;
  time.timeZone = "UTC";
}
