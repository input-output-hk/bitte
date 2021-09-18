# real encrypted directory should be at the root of the flake
{ self, pkgs, ... }:
let
  fakeEncrypted = pkgs.stdenvNoCC.mkDerivation {
    name = "fake-encrypted-dir";
    dontBuild = true;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/encrypted
      echo {} > $out/encrypted/consul-clients.json
      echo {} > $out/encrypted/nix-builder-key
    '';
  };
in { secrets.encryptedRoot = "${fakeEncrypted}/encrypted"; }
