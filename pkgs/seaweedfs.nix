{ stdenv, buildGoModule, fetchFromGitHub }:

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
    rev = "91fd311f7a7e84217f4dde536de50e31948b669b";
    sha256 = "sha256-WOqUqwyWY69adiJ3AHuIYMmqjUz72o0kengwdMe7zkA=";
  };

  subPackages = [ "weed" ];

  vendorSha256 = "sha256-9i+ynECjHHwsZhkaR+cg/kVta2wTugIJiqsIT+JTWPs=";

  meta = with stdenv.lib; {
    description = "Tool for service discovery, monitoring and configuration";
    homepage = "https://www.consul.io/";
    platforms = platforms.linux ++ platforms.darwin;
    license = licenses.mpl20;
    maintainers = with maintainers; [ pradeepchhetri vdemeester nh2 ];
  };
}
