{ pkgs, lib, buildGoModule, fetchFromGitHub, fetchurl, nixosTests }:

buildGoModule rec {
  pname = "consul";
  version = "1.10.1";
  rev = "v${version}";

  # Note: Currently only release tags are supported, because they have the Consul UI
  # vendored. See
  #   https://github.com/NixOS/nixpkgs/pull/48714#issuecomment-433454834
  # If you want to use a non-release commit as `src`, you probably want to improve
  # this derivation so that it can build the UI's JavaScript from source.
  # See https://github.com/NixOS/nixpkgs/pull/49082 for something like that.
  # Or, if you want to patch something that doesn't touch the UI, you may want
  # to apply your changes as patches on top of a release commit.
  src = fetchFromGitHub {
    owner = "hashicorp";
    repo = pname;
    inherit rev;
    sha256 = "sha256-oap0pXqtIbT9wMfD/RuJ2tTRynSvfzsgL8TyY4nj3sM=";
  };

  patches = [
    ./script-check.patch
    # Fix no http protocol upgrades through envoy
    ./consul-issue-9639.patch
    # Fix no envoy upstream listener issue specific to Consul v1.10.1
    (if version == "1.10.1" then (pkgs.fetchpatch {
      name = "consul-issue-10714-patch";
      url = "https://github.com/hashicorp/consul/commit/3e2ec34409babda7f625889f3620c9d3810521fc.patch";
      sha256 = "sha256-H+LhhISrM829yn93SfIsJzD0JgTPfPoBIzfZ30TLIek=";
    }) else null)
  ];

  passthru.tests.consul = nixosTests.consul;

  # This corresponds to paths with package main - normally unneeded but consul
  # has a split module structure in one repo
  subPackages = [ "." "connect/certgen" ];

  vendorSha256 = "sha256-ZhHjMLLTN4PP60n2ejU+C3xt3PGGURVC+aq3GgLl7A4=";
  deleteVendor = true;

  preBuild = ''
    buildFlagsArray+=("-ldflags"
                      "-X github.com/hashicorp/consul/version.GitDescribe=v${version}
                       -X github.com/hashicorp/consul/version.Version=${version}
                       -X github.com/hashicorp/consul/version.VersionPrerelease=")
  '';

  meta = with lib; {
    description = "Tool for service discovery, monitoring and configuration";
    homepage = "https://www.consul.io/";
    platforms = platforms.linux ++ platforms.darwin;
    license = licenses.mpl20;
    maintainers = with maintainers; [ pradeepchhetri vdemeester nh2 ];
  };
}
