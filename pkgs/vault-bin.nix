{ stdenv, fetchurl, unzip, makeWrapper, gawk, glibc }:

let
  version = "1.6.0";

  sources = let base = "https://releases.hashicorp.com/vault/${version}";
  in {
    x86_64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_amd64.zip";
      sha256 = "sha256-gwSOLR6/6iEv6tQuR06UfDo7zMUFalFY7TP1MPgyXjk=";
    };
    x86_64-darwin = fetchurl {
      url = "${base}/vault_${version}_darwin_amd64.zip";
      sha256 = "sha256-EOqQtR1muFSD0Weqtr3EOj4f/PpW9uJHhMCj08uYgUI=";
    };
    aarch64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_arm64.zip";
      sha256 = "sha256-//E8f3U+vunr6ojoH12N+j1i8V6g765Ch/CaTkIsCgU=";
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
      --set PATH ${stdenv.lib.makeBinPath [ gawk glibc ]}
  '';

  meta = with stdenv.lib; {
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
