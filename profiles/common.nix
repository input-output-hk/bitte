{ config, lib, ... }:
let cfg = config.cluster; in
{
  imports = [ ./nix.nix ./ssh.nix ./slim.nix ./promtail.nix ];

  services = {
    amazon-ssm-agent.enable = true;
    vault.enable = true;
    consul.enable = true;
  };

  environment.variables = { AWS_DEFAULT_REGION = cfg.region; };

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = false;
  services.openntpd.enable = true;
  networking.timeServers = lib.mkForce [
    "0.nixos.pool.ntp.org"
    "1.nixos.pool.ntp.org"
    "2.nixos.pool.ntp.org"
    "3.nixos.pool.ntp.org"
  ];
  boot.cleanTmpDir = true;
  networking.firewall.allowPing = true;
  # TODO: enable again
  networking.firewall.enable = false;
  time.timeZone = "UTC";
  security.pki.certificateFiles = lib.mkIf cfg.letsEncrypt.useStaging
    [ ./acme-staging-root.pem ];
}
