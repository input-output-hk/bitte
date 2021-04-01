{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "oauth2-proxy";
  version = "7.0.1";

  src = fetchFromGitHub {
    repo = pname;
    owner = "oauth2-proxy";
    sha256 = "sha256-VmVVEkOLY6NjjxGx2sZkj3+LW/aTAe0YINZ9HFy38MU=";
    rev = "76269a13b72afa1e46be799e2d835cfab406c1cf";
  };

  vendorSha256 = "sha256-d7gX/fFGTGHyO6buicyvBARc1zhy5BQWRMwLV9w3Z2s=";

  # Taken from https://github.com/oauth2-proxy/oauth2-proxy/blob/master/Makefile
  buildFlagsArray = ("-ldflags=-X main.VERSION=${version}");

  meta = with lib; {
    description =
      "A reverse proxy that provides authentication with Google, Github, or other providers";
    homepage = "https://github.com/oauth2-proxy/oauth2-proxy/";
    license = licenses.mit;
    maintainers = with maintainers; [ yorickvp knl ];
  };
}
