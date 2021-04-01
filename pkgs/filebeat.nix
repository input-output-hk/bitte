{ lib, buildGoModule, fetchFromGitHub, systemd }:
buildGoModule rec {
  pname = "beats";
  version = "7.12.0";

  src = fetchFromGitHub {
    owner = "elastic";
    repo = "beats";
    rev = "v${version}";
    sha256 = "sha256-CnTEZQ3exZSn8vhDguWhALLySh4lmXEPTWdAqWPU4bI=";
  };

  vendorSha256 = "sha256-Pd8jE7fAYQ/Js39X+8d1ojcGzxAg5MQkYqY2PB8CXa4=";

  subPackages = [ "filebeat" ];
  buildInputs = [ systemd.dev ];
}
