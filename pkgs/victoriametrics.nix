{ lib, buildGoPackage, fetchFromGitHub }:

buildGoPackage rec {
  pname = "VictoriaMetrics";
  version = "1.49.0";

  src = fetchFromGitHub {
    owner = pname;
    repo = pname;
    rev = "v${version}";
    sha256 = "1aa9dlz2b757xzn0plix7p115kxh5rpa12ad86wzybxs778wgb4n";
  };

  goPackagePath = "github.com/VictoriaMetrics/VictoriaMetrics";

  buildFlagsArray = [ "-ldflags=-s -w -X ${goPackagePath}/lib/buildinfo.Version=${version}" ];

  meta = with lib; {
    homepage = "https://victoriametrics.com/";
    description = "fast, cost-effective and scalable time series database, long-term remote storage for Prometheus";
    license = licenses.asl20;
    maintainers = [ maintainers.yorickvp ];
  };
}
