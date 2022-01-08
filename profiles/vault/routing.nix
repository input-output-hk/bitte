{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ]; };

  Switches = {
    services.vault-agent-monitoring.enable = true;
  };

  Config = { };

in Imports // lib.mkMerge [
  Switches
  Config
]
