{ lib }:
let
  inherit (builtins) attrNames readDir;
  inherit (lib) filterAttrs hasSuffix removeSuffix mapAttrs' nameValuePair;

  # mapFilterAttrs ::
  #   (name -> value -> bool )
  #   (name -> value -> { name = any; value = any; })
  #   attrs
  mapFilterAttrs = sieve: f: attrs: filterAttrs sieve (mapAttrs' f attrs);

  recImport = { dir, _import ? base: builtins.trace "importing ${toString dir} ${base}" (import (dir + "/${base}.nix")) }:
  mapFilterAttrs (_: v: v != null) (n: v:
  if n != "default.nix"
  && ((hasSuffix ".nix" n && v == "regular") || v == "directory")

  then let
    baseName = removeSuffix ".nix" n;
  in nameValuePair (baseName) (if v == "regular" then _import baseName else recImport { dir = dir + "/${baseName}"; })

  else nameValuePair ("") (null)) (readDir dir);

in recImport

