# Load docker developer password into vault
{ terralib, ... }:
let inherit (terralib) var;
in {
  tf.hydrate-cluster.configuration = {

    data.sops_file.docker-developer-password.source_file =
      "./encrypted/docker-passwords.json";
    resource.vault_generic_secret.docker-developer-password = {
      path = "kv/nomad-cluster/docker-developer-password";
      data_json = var "data.sops_file.docker-developer-password.raw";
    };

  };
}
