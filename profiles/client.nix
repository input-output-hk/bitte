{ self, pkgs, config, lib, ... }: {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./docker.nix
    ./nomad/client.nix
    ./nomad/bridge-lo-fixup.nix
    ./telegraf.nix
    ./vault/client.nix
    ./secrets.nix
    ./reaper.nix
    ./builder.nix
  ];

  services = {
    amazon-ssm-agent.enable = true;
    vault-agent-client = {
      enable = true;
      disableTokenRotation = {
        consulAgent = true;
        consulDefault = true;
      };
    };
    vault.enable = lib.mkForce false;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-client";
  };

  boot.cleanTmpDir = true;

  time.timeZone = "UTC";

  networking = { hostId = "9474d585"; };
}
