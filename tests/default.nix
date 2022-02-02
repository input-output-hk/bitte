{ self, pkgs }:

{
  simple-cluster = self.lib.mkBitteStack {
    inherit self pkgs;
    inherit (self) inputs;
    clusters = "${self}/tests/simple-cluster";
    hydrateModule = "${self}/tests/simple-cluster/hydrate.nix";
    deploySshKey = "/homeless-shelter/doesnt-exist";
    domain = "example.com";
  };
}

