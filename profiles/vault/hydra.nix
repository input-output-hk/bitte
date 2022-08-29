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
  };

  Config = {
    services.vault-agent.role = "hydra";
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
