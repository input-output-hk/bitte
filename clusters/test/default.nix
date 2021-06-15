{ ... }: {
  age.encryptedRoot = ../../encrypted;

  cluster = {
    name = "test";
    domain = "test.local";
    flakePath = ../../.;

    # TODO: get rid of these
    kms = "";
    region = "local";
    s3Bucket = "";
    s3CachePubKey = "";

    instances = {
      core0 = {
        privateIP = "172.16.0.10";
        modules = [ ../../profiles/core.nix ];
      };

      core1 = {
        privateIP = "172.16.1.10";
        modules = [ ../../profiles/core.nix ];
      };

      core2 = {
        privateIP = "172.16.2.10";
        modules = [ ../../profiles/core.nix ];
      };

      work0 = {
        privateIP = "172.16.3.1";
        modules = [ ../../profiles/work.nix ];
        datacenter = "dc0";
      };
    };
  };
}
