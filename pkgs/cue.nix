{ buildGoModule, fetchgit, lib }:

buildGoModule rec {
  pname = "cue";
  version = "0.3.0";

  src = fetchgit {
    url = "https://cue.googlesource.com/cue";
    rev = "447606047bdd32f79029a4be5424af3a09ea15f2";
    sha256 = "sha256-tafAkQGn2aT6A1u7OeAfsZSST3bRshFPye3Y+noCaMA=";
  };

  vendorSha256 = "sha256-d8p/vsbJ/bQbT2xrqqCoU1sQB8MrwKOMwEYhNYTWe4I=";

  doCheck = false;

  subPackages = [ "cmd/cue" ];

  buildFlagsArray = [
    "-ldflags=-X cuelang.org/go/cmd/cue/cmd.version=${version}"
  ];

  meta = {
    description = "A data constraint language which aims to simplify tasks involving defining and using data";
    homepage = "https://cuelang.org/";
    maintainers = with lib.maintainers; [ solson ];
    license = lib.licenses.asl20;
  };
}
