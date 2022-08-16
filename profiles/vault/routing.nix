{
  config,
  lib,
  pkgs,
  ...
}: let
  Imports = {
    imports = [
      ./common.nix
    ];
  };

  Switches = {
    services.vault-agent.disableTokenRotation.consulAgent = true;
    services.vault-agent.disableTokenRotation.consulDefault = true;
    services.vault-agent.disableTokenRotation.routing = true;
  };

  Config = {
    services.vault-agent.role = "routing";
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
