{ stdenv, fetchzip }:
stdenv.mkDerivation rec {
  pname = "nomad-autoscaler";
  version = "0.1.0";

  src = fetchzip {
    sha256 = "sha256-jmvCJf37TLyY1lXmrEp3VPSBJaMORI+YHGt3y9sIMUo=";
    url =
      "https://releases.hashicorp.com/nomad-autoscaler/${version}/nomad-autoscaler_${version}_linux_amd64.zip";
  };

  installPhase = ''
    install -m0777 -D $src/nomad-autoscaler $out/bin/nomad-autoscaler
  '';
}
