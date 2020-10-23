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
    rev = "b81359823fdd8dca0edf812303cd1d441e0dce3f";
    sha256 = "sha256-WI9Okh/yyiMIIKWICyR9JmXKwIhjoObV2Uqu7CHB3fE=";
  };

  subPackages = [ "weed" ];

  vendorSha256 = "sha256-mQbZiUCFlMoAGKcIfc6jLbLTDnbQqZX8xGJon+s0Ppw=";

  meta = with stdenv.lib; {
    description = "Tool for service discovery, monitoring and configuration";
    homepage = "https://www.consul.io/";
    platforms = platforms.linux ++ platforms.darwin;
    license = licenses.mpl20;
    maintainers = with maintainers; [ pradeepchhetri vdemeester nh2 ];
  };
}
