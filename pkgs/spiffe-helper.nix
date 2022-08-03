{
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchpatch,
}:
buildGoModule rec {
  pname = "spiffe-helper";
  version = "0.5";

  src = fetchFromGitHub {
    owner = "spiffe";
    repo = pname;
    rev = version;
    sha256 = "0v3g6ls1d0493vrawhgq72wyv1nc2k6dwbf7sras6fjqvk2jya65";
  };

  patches = [
    # Move to go-spiffe/v2 API
    (fetchpatch {
      url = "https://patch-diff.githubusercontent.com/raw/spiffe/spiffe-helper/pull/25.patch";
      sha256 = "sha256-cAEp9T0uXRM6E9D7yXsKSzGgdGFArCtyMYoP0h9g7j0=";
    })
  ];

  vendorSha256 = "sha256-f1AougFjmlIAJiieaTSvCPvzT1SEVB8a8PvZ0ZXSdrw=";

  subPackages = ["cmd/spiffe-helper"];

  meta = with lib; {
    description = "The SPIFFE Helper is a tool that can be used to retrieve and manage SVIDs on behalf of a workload";
    homepage = "https://github.com/spiffe/spiffe-helper";
    license = licenses.asl20;
    maintainers = with maintainers; [blaggacao];
  };
}
