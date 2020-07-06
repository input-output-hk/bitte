{ nixpkgs, lib }:
let
  inherit (lib)
    hasSuffix nameValuePair filterAttrs readDir mapAttrs' removeSuffix;

  mapFilterAttrs = sieve: f: attrs: filterAttrs sieve (mapAttrs' f attrs);
  dir = ../modules;
  paths = builtins.readDir dir;

  local = mapFilterAttrs (key: value: value != null) (name: type:
    nameValuePair (removeSuffix ".nix" name)
    (if name != "default.nix" && type == "regular" && hasSuffix ".nix" name then
      (import (dir + "/${name}"))
    else
      null)) paths;
in local // {
  amazon-image =
    import (nixpkgs + "/nixos/modules/virtualisation/amazon-image.nix");
}

