{
  buildGoPackage,
  fetchFromGitHub,
  lib,
}:
buildGoPackage rec {
  pname = "distribution";
  version = "2.8.1-unstable";

  goPackagePath = "github.com/distribution/distribution";

  src = fetchFromGitHub {
    owner = "distribution";
    repo = "distribution";
    rev = "0eca2112940978476d08501eccdcb6a9996804f7";
    sha256 = "sha256-6A6Gyrfyg6GT/PJ4Fjgu/+itotF/Z+t4dp1Q/Yx6n6E=";
  };

  meta = with lib; {
    description = "The Docker toolset to pack, ship, store, and deliver content";
    license = licenses.asl20;
    maintainers = [maintainers.globin];
    platforms = platforms.unix;
  };
}
