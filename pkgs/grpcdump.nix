{
  stdenv,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "grpcdump";
  version = "1.0.0";

  # Note: Currently only release tags are supported, because they have the Consul UI
  # vendored. See
  #   https://github.com/NixOS/nixpkgs/pull/48714#issuecomment-433454834
  # If you want to use a non-release commit as `src`, you probably want to improve
  # this derivation so that it can build the UI's JavaScript from source.
  # See https://github.com/NixOS/nixpkgs/pull/49082 for something like that.
  # Or, if you want to patch something that doesn't touch the UI, you may want
  # to apply your changes as patches on top of a release commit.
  src = fetchFromGitHub {
    owner = "rmedvedev";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-5N9uPyXiOGx6kUkgt6htK54wqJf97wPW5bUNNFieoA8=";
  };

  subPackages = ["cmd/grpcdump"];

  vendorSha256 = "sha256-KuywlRwL3ULMPbRzsgaAzhCg7p+SqpOMKag/gvBHP08=";
}
