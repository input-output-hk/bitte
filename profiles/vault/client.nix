{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ./common.nix ]; };

  Switches = {};

  Config = {};

in Imports // lib.mkMerge [
  Switches
  Config
]
