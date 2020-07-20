{ stdenv, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "consul-template";
  version = "0.25.0";
  rev = "v${version}";

  # goPackagePath = "github.com/hashicorp/consul-template";
  # subPackages = [ "." ];

  vendorSha256 = "sha256-HdzV+B+5KJNO3B0I7uYfxazzSU6jG2hdpNSEod60ZYI=";

  src = fetchFromGitHub {
    inherit rev;
    owner = "hashicorp";
    repo = "consul-template";
    sha256 = "sha256-I7MyRUSFJR6PHp6tYZjc4SBRI3ONPg9FaMOjFRpRjnY=";
  };

  meta = with stdenv.lib; {
    homepage = "https://github.com/hashicorp/consul-template/";
    description = "Generic template rendering and notifications with Consul";
    platforms = platforms.linux ++ platforms.darwin;
    license = licenses.mpl20;
    maintainers = with maintainers; [ pradeepchhetri ];
  };
}
