{ config, ... }: {
  imports = [ ./nix.nix ./ssh.nix ./slim.nix ];

  services = {
    s3-download.enable = true;
    amazon-ssm-agent.enable = true;
    nomad.enable = true;
    vault.enable = true;
    consul.enable = true;
  };

  disabledModules =
    [ "services/security/vault.nix" "services/networking/consul.nix" ];

  environment.variables = { AWS_DEFAULT_REGION = config.cluster.region; };

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = false;
  boot.cleanTmpDir = true;
  networking.firewall.allowPing = true;
  # TODO: enable again
  networking.firewall.enable = false;
  time.timeZone = "UTC";
}
