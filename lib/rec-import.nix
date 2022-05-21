{lib}: let
  # mapFilterAttrs ::
  #   (name -> value -> bool )
  #   (name -> value -> { name = any; value = any; })
  #   attrs
  mapFilterAttrs = sieve: f: attrs:
    lib.filterAttrs sieve (lib.mapAttrs' f attrs);

  recImport = {
    dir,
    _import ? base:
      builtins.trace "importing ${toString dir} ${base}"
      (import (dir + "/${base}.nix")),
  }:
    mapFilterAttrs (_: v: v != null) (n: v:
      if
        n
        != "default.nix"
        && ((lib.hasSuffix ".nix" n && v == "regular") || v == "directory")
      then let
        baseName = lib.removeSuffix ".nix" n;
      in
        lib.nameValuePair baseName (
          if v == "regular"
          then _import baseName
          else recImport {dir = dir + "/${baseName}";}
        )
      else lib.nameValuePair "" null) (builtins.readDir dir);
in
  recImport
