{
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchpatch,
}:
buildGoModule rec {
  pname = "spiffe-helper";
  version = "16c09cad5e9734296f429fd9eb7986132650ce6b"; # 0.5

  src = fetchFromGitHub {
    owner = "spiffe";
    repo = pname;
    rev = version;
    hash = "sha256-jAPpW0o0aXUYOnRhunnuB+77nxmKNlz0qoRPXG50IVw=";
  };

  vendorSha256 = "sha256-WK6KVqzhp/L4Xc3Afq6QS5g83fmzvfaOyzvHZMwBRio=";

  subPackages = ["cmd/spiffe-helper"];

  meta = with lib; {
    description = "The SPIFFE Helper is a tool that can be used to retrieve and manage SVIDs on behalf of a workload";
    homepage = "https://github.com/spiffe/spiffe-helper";
    license = licenses.asl20;
    maintainers = with maintainers; [blaggacao];
  };
}
