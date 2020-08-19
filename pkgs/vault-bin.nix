{ stdenv, fetchurl, unzip, makeWrapper, gawk, glibc }:

let
  version = "1.5.0";

  sources = let base = "https://releases.hashicorp.com/vault/${version}";
  in {
    x86_64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_amd64.zip";
      sha256 = "183kpk6pf978hl54v3cvwmhsiwqs8sgxzqgrqlgp3i21w6p968rj";
    };
    i686-linux = fetchurl {
      url = "${base}/vault_${version}_linux_386.zip";
      sha256 = "06f1g2slfm7mvihg7v60a2368yc23mcmmlhrapmz0498y331kaxw";
    };
    x86_64-darwin = fetchurl {
      url = "${base}/vault_${version}_darwin_amd64.zip";
      sha256 = "0xs8a7hy334kqml4bwwjili3axm9qw4mq83rx8bcr4k15l1nzxqj";
    };
    i686-darwin = fetchurl {
      url = "${base}/vault_${version}_darwin_386.zip";
      sha256 = "1fzp41jag7njylvq2m1j3yvsqjvlajq6xx36z59r0smfyl8krlj9";
    };
    aarch64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_arm64.zip";
      sha256 = "06hcdb24ypzl9gz0v6n0v9s1qcs79qq6h0gssaq62rm8bzkm7svn";
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
