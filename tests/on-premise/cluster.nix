{ ... }: {
  age.encryptedRoot = ./encrypted;

  cluster = {
    name = "test";
    domain = "test.local";
    flakePath = ../../.;

    instances = {
      core0 = {
        privateIP = "172.16.0.10";
        modules = [ ../../hosts/prem/core.nix ];
      };

      core1 = {
        privateIP = "172.16.1.10";
        modules = [ ../../hosts/prem/core.nix ];
      };

      core2 = {
        privateIP = "172.16.2.10";
        modules = [ ../../hosts/prem/core.nix ];
      };

      work0 = {
        privateIP = "172.16.3.1";
        modules = [ ../../hosts/prem/work.nix ];
        datacenter = "dc0";
      };
    };
  };
}
