{ config, lib, pkgs, pkiFiles, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
in {
  age.secrets = lib.mkIf (deployType != "aws") {
    vault-full-server = {
      file = config.age.encryptedRoot + "/ssl/server-full.age";
      path = pkiFiles.serverCertChainFile;
      mode = "0644";
    };

    vault-full-client = {
      file = config.age.encryptedRoot + "/ssl/client-full.age";
      path = pkiFiles.clientCertChainFile;
      mode = "0644";
    };

    vault-ca = {
      file = config.age.encryptedRoot + "/ssl/ca.age";
      path = pkiFiles.vaultCaCertFile;
      mode = "0644";
    };

    vault-server = {
      file = config.age.encryptedRoot + "/ssl/server.age";
      path = pkiFiles.serverCertFile;
      mode = "0644";
    };

    vault-server-key = {
      file = config.age.encryptedRoot + "/ssl/server-key.age";
      path = pkiFiles.serverKeyFile;
      mode = "0600";
    };

    vault-client = {
      file = config.age.encryptedRoot + "/ssl/client.age";
      path = pkiFiles.clientCertFile;
      mode = "0644";
    };

    vault-client-key = {
      file = config.age.encryptedRoot + "/ssl/client-key.age";
      path = pkiFiles.clientKeyFile;
      mode = "0600";
    };
  };
}
