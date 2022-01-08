{ config, lib, pkgs, ... }: let

  Imports = { imports = [
    ./common.nix

    ./secrets-provisioning/hashistack.nix
    ./secrets-provisioning/letsencrypt-ingress.nix
  ]; };

  Switches = { };

  Config = {
    services.vault-agent.role = "core";
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
