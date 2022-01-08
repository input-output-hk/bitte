{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "systemd-attestor";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "input-output-hk";
    repo = pname;
    rev = "v${version}";
    sha256 = "0y1sp93yzqv4aq49sh2cwm72pxdfiqy0wa1w3wx7wzrk3ch30qq1";
  };

  vendorSha256 = "sha256-AobKAsCyfiwR8fawysa1hxF6AJAPq8K24UaKjhAqei0=";

  subPackages = [ "." ];

  meta = with lib; {
    description = "A systemd-attestor for SPIFFE/spire";
    homepage = "https://github.com/input-output-hk/systemd-attestor";
    license = licenses.asl20;
    maintainers = with maintainers; [ blaggacao ];
  };
}
