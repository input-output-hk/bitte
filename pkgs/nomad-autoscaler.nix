{ stdenv, fetchFromGitHub, buildGoModule }:
buildGoModule rec {
  pname = "nomad-autoscaler";
  version = "0.3.2";

  src = fetchFromGitHub {
    owner = "hashicorp";
    repo = "nomad-autoscaler";
    rev = "v${version}";
    sha256 = "sha256-fiVFKv89ZwEetSmZqMZDP33URy0iF/O90vnQMHp7h2g=";
  };

  subPackages = [ "." ];

  vendorSha256 = "sha256-hU8aOQMOSSRs1+/2yUinh6w0PjmefpkC3NQtqG3YxCY=";
}
