{
  pkgs,
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
  nixosTests,
}:
buildGoModule rec {
  pname = "consul";
  version = "1.13.1";
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
    sha256 = "sha256-Svclb+tLb0gk3xhoslVvAZZf0LR2M5nR9BmMYLBBHck=";
  };

  patches = [
    ./script-check.patch
    # Fix no http protocol upgrades through envoy
    # Refs:
    #   https://github.com/hashicorp/consul/issues/8283
    #   https://github.com/hashicorp/consul/pull/9639
    #   https://github.com/hashicorp/consul/pull/13418
    ./consul-issue-8283.patch
    # https://github.com/hashicorp/consul/issues/12145
    ./pr-12560-deregister-sunken-token.patch
    # Add an envoy route idle_timeout config knob
    # Follows: https://github.com/hashicorp/consul/pull/9554
    ./consul-idle-timeout.patch
  ];

  passthru.tests.consul = nixosTests.consul;

  # This corresponds to paths with package main - normally unneeded but consul
  # has a split module structure in one repo
  subPackages = ["." "connect/certgen"];

  vendorSha256 = "sha256-bPfS8hoH45ad34CsR+9WLEDCDsx1E/ZKdipVZqirfDY=";

  ldflags = [
    "-X github.com/hashicorp/consul/version.GitDescribe=v${version}"
    "-X github.com/hashicorp/consul/version.Version=${version}"
    "-X github.com/hashicorp/consul/version.VersionPrerelease="
  ];

  meta = with lib; {
    description = "Tool for service discovery, monitoring and configuration";
    homepage = "https://www.consul.io/";
    platforms = platforms.linux ++ platforms.darwin;
    license = licenses.mpl20;
    maintainers = with maintainers; [pradeepchhetri vdemeester nh2 techknowlogick];
  };
}
