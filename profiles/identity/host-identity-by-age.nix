{
  config,
  lib,
  pkgs,
  pkiFiles,
  ...
}: let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  role = config.currentCoreNode.role or config.currentAwsAutoScalingGroup.role;
  isRouter = role == "router";
  isServer = (config.services.vault-agent.role == "core") || config.services.consul.server || config.services.nomad.server.enabled;
in {
  age.secrets = lib.mkIf (deployType != "aws") {
    vault-full-server = lib.mkIf (isServer || isRouter) {
      file = config.age.encryptedRoot + "/ssl/server-full.age";
      path = pkiFiles.serverCertChainFile;
      mode = "0644";
    };

    vault-full-client = {
      file = config.age.encryptedRoot + "/ssl/client-full.age";
      path = pkiFiles.clientCertChainFile;
      mode = "0644";
    };

    # Avoid this on clients in prem envs since client will
    # cert authenticate to vault via agent and then write
    # out a ca_chain including the intermediate to ca.pem
    #
    # Pushing this only to servers will avoid collision
    # of ca.pem from age on deploy and vault-agent ca.pem.
    vault-ca = lib.mkIf (isServer || isRouter) {
      file = config.age.encryptedRoot + "/ssl/ca.age";
      path = pkiFiles.caCertFile;
      mode = "0644";
    };

    vault-server = lib.mkIf (isServer || isRouter) {
      file = config.age.encryptedRoot + "/ssl/server.age";
      path = pkiFiles.serverCertFile;
      mode = "0644";
    };

    vault-server-key = lib.mkIf (isServer || isRouter) {
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
