{ ... }:
let hosts = (import ../../hosts { }).prem;
in {
  age.encryptedRoot = ./encrypted;

  cluster = {
    name = "test";
    domain = "test.local";
    flakePath = ../../.;

    instances = {
      core0 = {
        privateIP = "172.16.0.10";
        modules = hosts.core;
      };

      core1 = {
        privateIP = "172.16.1.10";
        modules = hosts.core;
      };

      core2 = {
        privateIP = "172.16.2.10";
        modules = hosts.core;
      };

      client0 = {
        privateIP = "172.16.3.1";
        modules = hosts.client;
      };
    };
  };
}
