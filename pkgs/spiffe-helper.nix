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
      sha256 = "sha256-sqJv/d5ybpxJ6l1yT881Gx+9HXZStvJqFnpBPG7SaWw=";
    })
  ];

  vendorSha256 = "sha256-Yzc9TGBszEJbr9ZMHxKmohoAfc8zEdx37w9ekdi+gAM=";

  subPackages = ["cmd/spiffe-helper"];

  meta = with lib; {
    description = "The SPIFFE Helper is a tool that can be used to retrieve and manage SVIDs on behalf of a workload";
    homepage = "https://github.com/spiffe/spiffe-helper";
    license = licenses.asl20;
    maintainers = with maintainers; [blaggacao];
  };
}
