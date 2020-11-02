{ stdenv, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "boundary";
  version = "0.1.1";
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
    sha256 = "sha256-o/8n6SeYRBIaazUu5aOfE37F20jCx2CLHX1UTnJj8CA=";
  };

  # This corresponds to paths with package main - normally unneeded but consul
  # has a split module structure in one repo
  subPackages = [ "." ];

  vendorSha256 = "sha256-mWW1LGrkLaLC/D62Q+rm3fCQ6HGZORRx3AcmN6w5JX8=";
  deleteVendor = true;

  preBuild = let
    tags = [ "ui" ];
    tagsString = stdenv.lib.concatStringsSep " " tags;
  in ''
    export buildFlagsArray=(
      -tags="${tagsString}"
    )
  '';
}
