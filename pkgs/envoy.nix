{ stdenv, lib, fetchurl, autoPatchelfHook }:

# Download URLs are at https://tetrate.bintray.com/getenvoy/manifest.json

stdenv.mkDerivation rec {
  pname = "envoy";
  version = "1.14.3.p0.g8fed485-1p67.g2aa564b";

  src = fetchurl {
    url =
      "https://dl.bintray.com/tetrate/getenvoy/getenvoy-envoy-${version}-linux-glibc-release-x86_64.tar.xz";
    sha256 = "sha256-5qAWzm1tEOj9rymBfOt3ptSWIAIKzkz32cxfxVPFsy4=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  unpackPhase = ''
    tar xvf $src
    find . -name envoy | xargs -I X mv X .
  '';

  installPhase = ''
    mkdir -p $out/bin
    mv envoy $out/bin
  '';
}
