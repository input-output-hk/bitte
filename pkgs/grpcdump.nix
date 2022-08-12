{
  stdenv,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "grpcdump";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "rmedvedev";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-5N9uPyXiOGx6kUkgt6htK54wqJf97wPW5bUNNFieoA8=";
  };

  subPackages = ["cmd/grpcdump"];

  vendorSha256 = "sha256-KuywlRwL3ULMPbRzsgaAzhCg7p+SqpOMKag/gvBHP08=";
}
