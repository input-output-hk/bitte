{ config, lib, pkgs, ... }: let

  Imports = { imports = [
    ./common.nix
  ]; };

  Switches = { };

  Config = {
    services.vault-agent.role = "routing";
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
