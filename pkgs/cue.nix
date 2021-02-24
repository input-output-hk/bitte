{ buildGoModule, fetchgit, lib }:

buildGoModule rec {
  pname = "cue";
  version = "0.3.0-beta.5";

  src = fetchgit {
    url = "https://cue.googlesource.com/cue";
    rev = "38f0f63459188f7e93cb146a408e7cc9cff77fd0";
    sha256 = "sha256-rqB5HOdppWwW2J8qiS+ffxu55yUcntD9CRCPbnjhMIQ=";
  };

  vendorSha256 = "sha256-9ai1Wbk6ftcXHjVEWaL8drxZnhgAwF8+OXNI95CrNjc=";

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
