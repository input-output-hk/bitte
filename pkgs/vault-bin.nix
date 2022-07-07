{ stdenv, lib, fetchurl, unzip, makeWrapper, gawk, glibc }:

let
  version = "1.11.0";

  # Hashes for misc systems and architectures can be obtained with:
  #   curl -OL https://releases.hashicorp.com/vault/${version}/vault_${version}_${system}_${arch}.zip
  #   nix-hash --flat --base32 --type sha256 vault_${version}_${system}_${arch}.zip | nix hash to-sri --type sha256 $(cat -)
  sources = let base = "https://releases.hashicorp.com/vault/${version}";
  in {
    x86_64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_amd64.zip";
      sha256 = "sha256-AOxCvtdWgMRAoW0WwZarB6EBIlVEjeNq9wnsGfHFuVc=";
    };
    x86_64-darwin = fetchurl {
      url = "${base}/vault_${version}_darwin_amd64.zip";
      sha256 = "sha256-UDwMC+Bf01EWzNFcrpcOF/IZOzGx70s8mRVvGrKNhYk=";
    };
    aarch64-linux = fetchurl {
      url = "${base}/vault_${version}_linux_arm64.zip";
      sha256 = "sha256-5IOxc77YTfRT9vEduiX/okVIN0GQZSmDqWIjy1D9tG4=";
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
