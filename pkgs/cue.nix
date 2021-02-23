{ buildGoModule, fetchgit, lib }:

buildGoModule rec {
  pname = "cue";
  version = "0.3.0-beta.5";

  src = fetchgit {
    url = "https://cue.googlesource.com/cue";
    rev = "v${version}";
    sha256 = "sha256-H3PCMM7oVsZx6pVveIEeZjv6KcevhSL9NOhh3j3mS0Q=";
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
