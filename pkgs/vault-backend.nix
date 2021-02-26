{ stdenv, buildGoPackage, nomad-source }:

buildGoPackage rec {
  pname = "vault-backend";
  version = "0.3.0";
  rev = "v${version}";

  goPackagePath = "github.com/gherynos/vault-backend";
  subPackages = [ "." ];

  src = fetchFromGitHub {
    owner = "gherynos";
    repo = "vault-backend";
    ref = rev;
    sha256 = "0000000000000000000000000000000000000000000000000000";
  };
}
