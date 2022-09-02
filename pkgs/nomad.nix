{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nixosTests,
}:
buildGoModule rec {
  pname = "nomad";
  version = "1.3.2";

  subPackages = ["."];

  src = fetchFromGitHub {
    owner = "hashicorp";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-GJul7slXNLEp+3l3OQ43ALVH3IscoCDDL7FG2UFtLG8=";
  };

  patches = [
    ./nomad/nomad-exec-nix-driver.patch
    # Addresses no nomad interpolation in connect envoy config
    # https://github.com/hashicorp/nomad/issues/14403
    ./nomad/nomad-interp-connect.patch
  ];

  vendorSha256 = "sha256-MqtkYHGIgeCFnbwE09xHgPMuJBSVHL0hB9RbwNX+K40=";

  # ui:
  #  Nomad release commits include the compiled version of the UI, but the file
  #  is only included if we build with the ui tag.
  tags = ["ui"];

  passthru.tests.nomad = nixosTests.nomad;

  meta = with lib; {
    homepage = "https://www.nomadproject.io/";
    description = "A Distributed, Highly Available, Datacenter-Aware Scheduler";
    platforms = platforms.unix;
    license = licenses.mpl20;
    maintainers = with maintainers; [rushmorem pradeepchhetri endocrimes maxeaubrey techknowlogick];
  };
}
