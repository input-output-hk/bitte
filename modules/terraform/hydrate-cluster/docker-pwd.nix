# Load docker developer password into vault
{ config, terralib, lib, ... }:
let
  inherit (terralib) var;
  inherit (config.cluster) infraType;
in {
  tf.hydrate-cluster.configuration = lib.mkIf (infraType != "prem") {

    data.sops_file.docker-developer-password.source_file =
      "${config.secrets.encryptedRoot + "/docker-passwords.json"}";
    resource.vault_generic_secret.docker-developer-password = {
      path = "kv/nomad-cluster/docker-developer-password";
      data_json = var "data.sops_file.docker-developer-password.raw";
    };

  };
}
