{ stdenv, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "consul-template";
  version = "0.25.1";
  rev = "v${version}";

  vendorSha256 = "sha256-wklYuJ98Ui0fChwHBdKZnkePL/Klsv/k/LOfiaZZZEM=";

  src = fetchFromGitHub {
    inherit rev;
    owner = "hashicorp";
    repo = "consul-template";
    sha256 = "sha256-q2SvXKMs5AC/uvTcjhZnkvJjRfFZC7ZsWPfHSjbMBYg=";
  };

  meta = with stdenv.lib; {
    homepage = "https://github.com/hashicorp/consul-template/";
    description = "Generic template rendering and notifications with Consul";
    platforms = platforms.linux ++ platforms.darwin;
    license = licenses.mpl20;
    maintainers = with maintainers; [ pradeepchhetri ];
  };
}
