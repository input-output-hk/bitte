/* Transit backend for sops encryption / decryption
   ATTENTION!
   Export the private keys and store them in vaultwarden
   Otherwise, secrets are lost if the cluster goes down.
*/
{ terralib, ... }:
let

  inherit (terralib) var;
in {
  tf.hydrate.configuration = {

    resource.vault_mount.sops = {
      path = "sops";
      type = "transit";
      description = "Sops encryption / decryption transit backend";
      default_lease_ttl_seconds = 3600;
      max_lease_ttl_seconds = 86400;
    };
    resource.vault_transit_secret_backend_key.ops = {
      backend = var "vault_mount.sops.path";
      name = "ops"; # devops
      allow_plaintext_backup = true; # enables key backup into vaultwarden
      exportable = true; # enables key backup into vaultwarden
    };
    resource.vault_transit_secret_backend_key.dev = {
      backend = var "vault_mount.sops.path";
      name = "dev"; # developers
      allow_plaintext_backup = true; # enables key backup into vaultwarden
      exportable = true; # enables key backup into vaultwarden
    };

  };
}
