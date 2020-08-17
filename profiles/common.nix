{ config, ... }: {
  imports = [ ./nix.nix ./ssh.nix ./slim.nix ./promtail.nix ];

  services = {
    amazon-ssm-agent.enable = true;
    vault.enable = true;
    consul.enable = true;
  };

  environment.variables = { AWS_DEFAULT_REGION = config.cluster.region; };

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = false;
  boot.cleanTmpDir = true;
  networking.firewall.allowPing = true;
  # TODO: enable again
  networking.firewall.enable = false;
  time.timeZone = "UTC";
}
