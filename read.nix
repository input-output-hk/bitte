let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  readDirRec = path:
    lib.pipe path [
      builtins.readDir
      (lib.filterAttrs (n: v: v == "directory" || n == "default.nix"))
      builtins.attrNames
      (map (name: path + "/${name}"))
      (map (child: if ( baseNameOf child ) == "default.nix" then child else readDirRec child ))
      lib.flatten
    ];

  result = readDirRec ./clusters;
in result
