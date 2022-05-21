/* Vault Mounts
  Mounts that are not _already_ necessary for bootstrapping.
*/
{ terralib, config, ... }:
let

  inherit (terralib) var id;

  runtimeSecretsPath = "runtime";
  starttimeSecretsPath = "starttime";

  __fromTOML = builtins.fromTOML;

in {
  tf.hydrate-cluster.configuration = {

    resource.vault_mount.${runtimeSecretsPath} = {
      path = "${runtimeSecretsPath}";
      type = "kv-v2";
      description =
        "Applications can (temporarily) access runtime secrets if they have access credentials for them";
    };
    resource.vault_mount.${starttimeSecretsPath} = {
      path = "${starttimeSecretsPath}";
      type = "kv-v2";
      description =
        "Nomad can access starttime secrets via its nomad-cluster role and pass these secrets via env variables";
    };

  };
}
