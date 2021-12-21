{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ./common.nix ]; };

  Switches = {};

  Config = {};

in lib.mkMerge [
  Imports
  Switches
  Config
]
