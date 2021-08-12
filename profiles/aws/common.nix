{ config, lib, ... }: {
  imports = [
    ../common.nix
    ./consul.nix
    ./nix.nix
    ./promtail.nix
    ./ssh.nix
    ./vault.nix
  ];

  environment.variables.AWS_DEFAULT_REGION = config.cluster.region;

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = false;
}

