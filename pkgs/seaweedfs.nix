# go get github.com/chrislusf/seaweedfs/weed
# https://github.com/chrislusf/seaweedfs/releases/tag/2.05

{ stdenv, buildGoModule, fetchFromGitHub, nixosTests }:

buildGoModule rec {
  pname = "seaweedfs";
  version = "2.05";

  # Note: Currently only release tags are supported, because they have the Consul UI
  # vendored. See
  #   https://github.com/NixOS/nixpkgs/pull/48714#issuecomment-433454834
  # If you want to use a non-release commit as `src`, you probably want to improve
  # this derivation so that it can build the UI's JavaScript from source.
  # See https://github.com/NixOS/nixpkgs/pull/49082 for something like that.
  # Or, if you want to patch something that doesn't touch the UI, you may want
  # to apply your changes as patches on top of a release commit.
  src = fetchFromGitHub {
    owner = "chrislusf";
    repo = pname;
    rev = version;
    sha256 = "sha256-1LvJ6B1vYFKLOBUwDtE39XdmGUhVCea2TcllRIKwVeQ=";
  };

  # passthru.tests.consul = nixosTests.consul;

  # This corresponds to paths with package main - normally unneeded but consul
  # has a split module structure in one repo
  subPackages = [ "weed" ];

  vendorSha256 = "sha256-Z92fyKYSz0JxZE5ZYrepdjRgZthIBVhEevFMY00kNxs=";
  deleteVendor = true;

  # preBuild = ''
  #   buildFlagsArray+=("-ldflags"
  #                     "-X github.com/hashicorp/consul/version.GitDescribe=v${version}
  #                      -X github.com/hashicorp/consul/version.Version=${version}
  #                      -X github.com/hashicorp/consul/version.VersionPrerelease=")
  # '';

  meta = with stdenv.lib; {
    description = "Tool for service discovery, monitoring and configuration";
    homepage = "https://www.consul.io/";
    platforms = platforms.linux ++ platforms.darwin;
    license = licenses.mpl20;
    maintainers = with maintainers; [ pradeepchhetri vdemeester nh2 ];
  };
}
