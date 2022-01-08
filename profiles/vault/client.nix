{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ]; };

  Switches = {
    services.vault-agent-client.enable = true;
  };

  Config = {
    services.vault-agent-client = {
      disableTokenRotation = {
        consulAgent = true;
        consulDefault = true;
      };
    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
