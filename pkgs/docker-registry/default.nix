{
  name,
  coreutils,
  lib,
  ruby,
  stdenv,
  writeShellApplication,
}: let
  inherit name;
  wrapperApp = writeShellApplication {
    inherit name;
    runtimeInputs = [coreutils ruby];
    text = ''exec ruby "$(dirname "$(readlink -f "$0")")/.${name}-wrapped" "$@"'';
  };
in
  stdenv.mkDerivation rec {
    inherit name;
    src = ./${name}.rb;

    dontUnpack = true;
    dontPatch = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      install -Dm555 "$src" "$out/bin/.${name}-wrapped"
      cp ${wrapperApp}/bin/${name} $out/bin
    '';
  }
