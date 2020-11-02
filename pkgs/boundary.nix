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
    sha256 = "sha256-Re3YcltmwstOrewdZbjPnAqxBg1ubQXLhyfBPtb+w7E=";
  };

  # This corresponds to paths with package main - normally unneeded but consul
  # has a split module structure in one repo
  subPackages = [ "." ];

  vendorSha256 = "snt6jshsOzHGRnqnhh8U1F1tZFLlsnFqQun0/SyE4/8=";
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
