{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "oauth2-proxy";
  version = "7.1.3";

  src = fetchFromGitHub {
    repo = pname;
    owner = "oauth2-proxy";
    sha256 = "sha256-zFXDv4in0zR7QdO7jg8ESKPBXEU+9bt/Desl7M6iKDg=";
    rev = "88122f641de3f7a5cc25a2bae121b07e04b8fe4b";
  };

  vendorSha256 = "sha256-DNcXHafuUIIYDI7uTcyCQbDVpkGWV+76NZFVK/HqkUM=";

  # This package will try to bind IP:Ports during tests and fail unless sandboxing is disabled
  doCheck = false;

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
