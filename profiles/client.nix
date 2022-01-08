{ self, pkgs, config, lib, ... }: {

  imports = [
    ./common.nix
    ./consul/client.nix
    ./nomad/client.nix
    ./vault/client.nix

    ./auxiliaries/docker.nix
    ./auxiliaries/reaper.nix
    ./auxiliaries/builder.nix
  ];

  services.s3-upload-flake.enable = true;
  services.zfs-client-options.enable = true;

  services.telegraf.extraConfig.global_tags.role = "consul-client";

  boot.cleanTmpDir = true;

  time.timeZone = "UTC";

  networking = { hostId = "9474d585"; };
}
