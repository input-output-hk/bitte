{ stdenv, lib, fetchurl, unzip, makeWrapper, gawk, glibc }:

let
  version = "1.7.3";

  sources = let base = "https://releases.hashicorp.com/vault/${version}";
  in {
    x86_64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_amd64.zip";
      sha256 = "sha256-hFMTKpO3VcCondSy8amb1K8G+BZ7gZF/EXCAg5Ax4D8=";
    };
    x86_64-darwin = fetchurl {
      url = "${base}/vault_${version}_darwin_amd64.zip";
      sha256 = "sha256-Ns8a48CwEfVNek37l+Dxr9jcPeQaGfM4tU2rJWEzhWs=";
    };
    aarch64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_arm64.zip";
      sha256 = "sha256-IwkvYNi8lrXEDOxx/skz524Ur7lSxc0bjVg1RZABXDA=";
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
      --set PATH ${lib.makeBinPath [ gawk glibc ]}
  '';

  meta = with lib; {
    homepage = "https://www.vaultproject.io";
    description = "A tool for managing secrets, this binary includes the UI";
    platforms = [
      "x86_64-linux"
      "i686-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "i686-darwin"
    ];
    license = licenses.mpl20;
    maintainers = with maintainers; [ offline psyanticy mkaito ];
  };
}
