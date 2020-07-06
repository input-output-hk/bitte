{ lib }:
let
  inherit (builtins) attrNames readDir;
  inherit (lib) filterAttrs hasSuffix mapAttrs' nameValuePair;

  # mapFilterAttrs ::
  #   (name -> value -> bool )
  #   (name -> value -> { name = any; value = any; })
  #   attrs
  mapFilterAttrs = sieve: f: attrs: filterAttrs sieve (mapAttrs' f attrs);

in { dir, _import ? base: import "${dir}/${base}.nix" }:
mapFilterAttrs (_: v: v != null) (n: v:
  if n != "default.nix"
  && ((hasSuffix ".nix" n && v == "regular" && false) || v == "directory")

  then
    let name = n; in nameValuePair (name) (_import name)

  else
    nameValuePair ("") (null)) (readDir dir)
