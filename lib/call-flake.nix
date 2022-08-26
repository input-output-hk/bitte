let
  url = "https://raw.githubusercontent.com/NixOS/nix/0c62b4ad0f80d2801a7e7caabf20cc8e50182540/src/libexpr/flake/call-flake.nix";
  callFlake = import (builtins.fetchurl {
    inherit url;
    sha256 = "sha256:1dmi01s1g3mnvb098iik3w38fxmkwg1q1ajk7mwk83kc5z13v2r7";
  });
in
  # flake can either be a flake ref expressed as an attribute set or a path to source tree
  flake: {
    # subdir of source root containing the flake.nix
    dir ? "",
  }: let
    src = builtins.fetchTree flake;
  in
    if dir == ""
    then callFlake (builtins.readFile "${src}/flake.lock") src dir
    else callFlake (builtins.readFile "${src}/${dir}/flake.lock") src dir
