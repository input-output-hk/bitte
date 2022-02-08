# Rationale:
#
# - Hydrate the cluster with backends, roles & policies
# - Hydrate vault with application secrets
# - Hydrate applications with initial state
# - NB: some things (still) auto-hydrate through systemd one-shot jobs
#       these could eventually be moved here.
{ self, lib, pkgs, config, terralib, ... }:
let
  inherit (terralib) regions awsProviderNameFor awsProviderFor;
  inherit (config.cluster) vbkBackend vbkBackendSkipCertVerification;

  vbkStub = "${vbkBackend}/state/${config.cluster.name}";

  tfConfig = { hydrateType, extraConfig ? { } }: {
    terraform.backend.http = {
      address = "${vbkStub}/hydrate-${hydrateType}";
      lock_address = "${vbkStub}/hydrate-${hydrateType}";
      unlock_address = "${vbkStub}/hydrate-${hydrateType}";
      skip_cert_verification = vbkBackendSkipCertVerification;
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  } // extraConfig;

in {

  # preconfigure hydrate-secrets
  tf.secrets-hydrate.configuration = abort ''

    secrets-hydrate has been renamed to hydrate-secrets.
    Please rename your infra cluster tf vault backend accordingly and switch!

    CLI Migration:
      # VAULT_ADDR would typically be: https://vault.infra.aws.iohkdev.io
      VAULT_ADDR=<VAULT_ADDR>
      VAULT_TOKEN=$VAULT_INFRA_OPS_ADMIN_TOKEN
      vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-secrets @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/secrets-hydrate | jq .data.data)

    Be sure to update your local hydrate.nix file with secrets-hydrate renamed to hydrate-secrets, otherwise:
      * TF will want to destroy your hydrate app secrets on the next plan/apply.
  '';
  tf.hydrate-secrets.configuration = tfConfig { hydrateType = "secrets"; };

  # preconfigure hydrate-app
  tf.app-hydrate.configuration = abort ''

    app-hydrate has been renamed to hydrate-app.
    Please rename your infra cluster tf vault backend accordingly and switch!

    CLI Migration:
      # VAULT_ADDR would typically be: https://vault.infra.aws.iohkdev.io
      VAULT_ADDR=<VAULT_ADDR>
      VAULT_TOKEN=$VAULT_INFRA_OPS_ADMIN_TOKEN
      vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-app @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/app-hydrate | jq .data.data)

    Be sure to update your local hydrate.nix file with app-hydrate renamed to hydrate-app, otherwise:
      * TF will want to destroy your hydrate app config on the next plan/apply.
  '';
  tf.hydrate-app.configuration = tfConfig { hydrateType = "app"; };

  # preconfigure hydrate-cluster
  tf.hydrate.configuration = abort ''

    hydrate has been renamed to hydrate-cluster.
    Please rename your infra cluster tf vault backend accordingly and switch!

    CLI Migration:
      # VAULT_ADDR would typically be: https://vault.infra.aws.iohkdev.io
      VAULT_ADDR=<VAULT_ADDR>
      VAULT_TOKEN=$VAULT_INFRA_OPS_ADMIN_TOKEN
      vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-cluster @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/hydrate | jq .data.data)

    Be sure to update your local hydrate.nix file with hydrate renamed to hydrate-cluster, otherwise:
      * TF will want to destroy your hydrate cluster config on the next plan/apply.
      * On the next bootstrapper deploy (ex: core-1), any hydrate cluster defined consul roles/policies will be purged causing job disruption.
  '';
  tf.hydrate-cluster.configuration = tfConfig {
    hydrateType = "cluster";
    extraConfig = {
      provider.aws = [{ inherit (config.cluster) region; }]
        ++ (lib.forEach regions (region: {
          inherit region;
          alias = awsProviderNameFor region;
        }));
    };
  };
}
