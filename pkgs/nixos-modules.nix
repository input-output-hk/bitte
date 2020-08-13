{ nixpkgs, lib }:
let
  inherit (lib)
    hasSuffix nameValuePair filterAttrs readDir mapAttrs' removeSuffix;

  mapFilterAttrs = sieve: f: attrs: filterAttrs sieve (mapAttrs' f attrs);
  dir = ../modules;
  paths = builtins.readDir dir;
in mapFilterAttrs (key: value: value != null) (name: type:
  nameValuePair (removeSuffix ".nix" name)
  (if name != "default.nix" && type == "regular" && hasSuffix ".nix" name then
    (import (dir + "/${name}"))
  else
    null)) paths

