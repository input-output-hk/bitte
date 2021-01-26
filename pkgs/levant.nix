{ stdenv, buildGoModule, levant-source }:

buildGoModule rec {
  pname = "levant";
  version = "0.3.0-beta1";
  goPackagePath = "github.com/hashicorp/levant";
  src = levant-source;
  subPackages = [ "." ];
  vendorSha256 = "sha256-fg/YPMKYXQSL6lVCenPLH3BV0T42RWKLSXmSLHDmlvk=";
}
