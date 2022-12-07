{
  lib,
  buildGo119Module,
  fetchFromGitHub,
  nixosTests,
}:
buildGo119Module rec {
  pname = "nomad";
  version = "1.4.3";

  subPackages = ["."];

  src = fetchFromGitHub {
    owner = "hashicorp";
    repo = pname;
    rev = "release/${version}";
    sha256 = "sha256-bk4kQSDqi4KuoPrTgbtveanc1TYUFsY9aVD0WmetjBc=";
  };

  patches = [
    ./nomad/nomad-exec-nix-driver.patch
  ];

  vendorSha256 = "sha256-JQRpsQhq5r/QcgFwtnptmvnjBEhdCFrXFrTKkJioL3A=";

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
