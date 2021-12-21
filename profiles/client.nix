{ self, pkgs, config, lib, ... }: {

  imports = [
    ./common.nix
    ./consul/client.nix
    ./nomad/client.nix

    ./docker.nix
    ./telegraf.nix
    ./secrets.nix
    ./reaper.nix
    ./builder.nix
    ./zfs-client-options.nix
  ];

  services.s3-upload-flake.enable = true;
  services.vault-agent-client.enable = true;

  services.telegraf.extraConfig.global_tags.role = "consul-client";
  services.vault-agent-client = {
    disableTokenRotation = {
      consulAgent = true;
      consulDefault = true;
    };
  };

  boot.cleanTmpDir = true;

  time.timeZone = "UTC";

  networking = { hostId = "9474d585"; };
}
