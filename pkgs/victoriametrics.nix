{ pkgs, lib, buildGoPackage, fetchFromGitHub }:

buildGoPackage rec {
  pname = "VictoriaMetrics";
  version = "1.68.0";

  src = fetchFromGitHub {
    owner = pname;
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-nTRlJISFyX42PCRWKH1tONFCQtAJ00fKw6521VDhvd0=";
  };

  goPackagePath = "github.com/VictoriaMetrics/VictoriaMetrics";

  ldflags =
    [ "-s" "-w" "-X ${goPackagePath}/lib/buildinfo.Version=${version}" ];

  # Avoid building the vmui component for now which requires a docker build
  preBuild = ''
    cd go/src/github.com/VictoriaMetrics/VictoriaMetrics/app/vmui/packages/vmui/web/
    touch asset-manifest.json index.html favicon-32x32.png manifest.json robots.txt static
  '';

  meta = with lib; {
    homepage = "https://victoriametrics.com/";
    description =
      "fast, cost-effective and scalable time series database, long-term remote storage for Prometheus";
    license = licenses.asl20;
    maintainers = [ maintainers.yorickvp ];
  };
}
