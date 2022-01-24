{ config, lib, pkgs, pkiFiles, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
in {
  age.secrets = lib.mkIf (deployType != "aws") {
    vault-full-server = {
      file = config.age.encryptedRoot + "/ssl/server-full.age";
      path = "/etc/ssl/certs/server-full.pem";
      mode = "0644";
    };

    vault-full-client = {
      file = config.age.encryptedRoot + "/ssl/client-full.age";
      path = "/etc/ssl/certs/client-full.pem";
      mode = "0644";
    };

    vault-ca = {
      file = config.age.encryptedRoot + "/ssl/ca.age";
      path = "/etc/ssl/certs/ca.pem";
      mode = "0644";
    };

    vault-server = {
      file = config.age.encryptedRoot + "/ssl/server.age";
      path = "/etc/ssl/certs/server.pem";
      mode = "0644";
    };

    vault-server-key = {
      file = config.age.encryptedRoot + "/ssl/server-key.age";
      path = "/etc/ssl/certs/server-key.pem";
      mode = "0600";
    };

    vault-client = {
      file = config.age.encryptedRoot + "/ssl/client.age";
      path = "/etc/ssl/certs/client.pem";
      mode = "0644";
    };

    vault-client-key = {
      file = config.age.encryptedRoot + "/ssl/client-key.age";
      path = "/etc/ssl/certs/client-key.pem";
      mode = "0600";
    };
  };
}
