{ config, lib, pkgs, ... }: let

  Imports = { imports = [
    ./common.nix
  ]; };

  Switches = { };

  Config = {
    services.vault-agent.role = "core";
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
