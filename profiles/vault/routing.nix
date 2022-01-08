{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ./common.nix ./core-secrets-templating.nix ]; };

  Switches = { };

  Config = {
    services.vault-agent.role = "core";
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
