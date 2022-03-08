{ terralib, config, ... }:
let

  inherit (terralib) var id;

  bwDevopsCollectionId = "0bfada24-1581-41ff-a264-00301ebf2df1";
  bwIogOrganizationId = "3bbffbd9-f0f8-4fb7-9d18-cca627081df0";

in {
  tf.hydrate-cluster.configuration = {

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

  tf.backup-transit-keys.configuration = {
    # backup to vaultwarden
    data.vault_generic_secret.sops-ops-key-backup = {
      depends_on = [ "vault_transit_secret_backend_key.ops" ];
      path = "sops/backup/ops";
    };
    data.vault_generic_secret.sops-dev-key-backup = {
      depends_on = [ "vault_transit_secret_backend_key.dev" ];
      path = "sops/backup/dev";
    };
    resource.bitwarden_item_secure_note."${config.cluster.name}-transit-keys-backup" = {
      name            = "${config.cluster.name}-transit-keys-backup";
      notes           = ''
      # App Secrets under version control

      - https://www.vaultproject.io/api-docs/secret/transit#backup-key
      - The recovery key-rings can be found below.
      - If the keys are rotated, a new backup must be included here
      '';
      favorite        = true;
      organization_id = bwIogOrganizationId;
      collection_ids = [ bwDevopsCollectionId ];

      field = [{
        name    = "ops-backup-key";
        text = var "data.vault_generic_secret.sops-ops-key-backup.data_json";
      }
      {
        name    = "dev-backup-key";
        text = var "data.vault_generic_secret.sops-dev-key-backup.data_json";
      }];

    };
    output.vaultwarden_transit_backup_item_id.value = id "bitwarden_item_secure_note.${config.cluster.name}-transit-keys-backup";
  };

  tf.restore-transit-keys.configuration = {
    data.bitwarden_item_secure_note."${config.cluster.name}-transit-keys-backup" = {
        id = "${config.cluster.vaultWardenTransitBackupItemId}";
    };
    resource.vault_generic_endpoint.sops-ops-key = {
      path                 = "sops/restore/ops";
      ignore_absent_fields = true;
      disable_read = true;
      disable_delete = true;

      data_json = var "jsonencode(data.bitwarden_item_secure_note.${config.cluster.name}-transit-keys-backup.field[0])";
    };
    resource.vault_generic_endpoint.sops-dev-key = {
      path                 = "sops/restore/dev";
      ignore_absent_fields = true;
      disable_read = true;
      disable_delete = true;

      data_json = var "jsonencode(data.bitwarden_item_secure_note.${config.cluster.name}-transit-keys-backup.field[1])";
    };
  };
}
