{ lib, stdenv, fetchurl, unzip, makeWrapper, gawk }:

let
  version = "1.6.4";

  sources = let base = "https://releases.hashicorp.com/vault/${version}";
  in {
    x86_64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_amd64.zip";
      sha256 = "sha256-7Lh5RhQAHyGHqEG0Xp1LrcGV79qzm/Kx7lSIG6HV3H8=";
    };
    x86_64-darwin = fetchurl {
      url = "${base}/vault_${version}_darwin_amd64.zip";
      sha256 = "sha256-QNuKGw4O0fC5L2FBQ3AiqtTlfPZqXmA9uKqU1cfOko8=";
    };
  };

in stdenv.mkDerivation {
  pname = "vault-bin";
  inherit version;

  src = sources.${stdenv.hostPlatform.system} or (throw
    "unsupported system: ${stdenv.hostPlatform.system}");

  nativeBuildInputs = [ unzip makeWrapper ];

  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out/bin $out/share/bash-completion/completions
    echo "complete -C $out/bin/vault vault" > $out/share/bash-completion/completions/vault

    mv vault $out/bin
    wrapProgram $out/bin/vault \
      --set PATH ${stdenv.lib.makeBinPath ([ gawk ] ++ lib.optionals stdenv.isLinux [ glibc ])}
  '';

  meta = with stdenv.lib; {
    homepage = "https://www.vaultproject.io";
    description = "A tool for managing secrets, this binary includes the UI";
    platforms = [
      "x86_64-linux"
      "x86_64-darwin"
    ];
    license = licenses.mpl20;
    maintainers = with maintainers; [ offline psyanticy mkaito ];
  };
}
