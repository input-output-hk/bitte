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

  vbkStub = "https://vbk.infra.aws.iohkdev.io/state/${config.cluster.name}";

in {

  # preconfigure hydrate-secrets
  tf.secrets-hydrate.configuration = lib.warn ''

    secrets-hydrate had been renamed to hydrate-secrets
    please rename your infra cluster tf vault backend accordingly
    and switch!


    VAULT_ADDR=https://vault.infra.aws.iohkdev.io
    VAULT_TOKEN=$TF_HTTP_PASSWORD
    vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-secrets @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/secrets-hydrate | jq .data.data)
  '' config.tf.hydrate-secrets.configuration;
  tf.hydrate-secrets.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/secrets-hydrate";
      lock_address = "${vbkStub}/secrets-hydrate";
      unlock_address = "${vbkStub}/secrets-hydrate";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  };

  # preconfigure hydrate-app
  tf.app-hydrate.configuration = lib.warn ''

    app-hydrate had been renamed to hydrate-app
    please rename your infra cluster tf vault backend accordingly
    and switch!


    VAULT_ADDR=https://vault.infra.aws.iohkdev.io
    VAULT_TOKEN=$TF_HTTP_PASSWORD
    vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-app @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/app-hydrate | jq .data.data)
  '' config.tf.hydrate-app.configuration;
  tf.hydrate-app.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/app-hydrate";
      lock_address = "${vbkStub}/app-hydrate";
      unlock_address = "${vbkStub}/app-hydrate";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  };

  # preconfigure hydrate-cluster
  tf.hydrate.configuration = lib.warn ''

    hydrate had been renamed to hydrate-cluster
    please rename your infra cluster tf vault backend accordingly
    and switch!


    VAULT_ADDR=https://vault.infra.aws.iohkdev.io
    VAULT_TOKEN=$TF_HTTP_PASSWORD
    vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-cluster @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/hydrate | jq .data.data)
  '' config.tf.hydrate-cluster.configuration;
  tf.hydrate-cluster.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/hydrate";
      lock_address = "${vbkStub}/hydrate";
      unlock_address = "${vbkStub}/hydrate";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
    provider.aws = [{ inherit (config.cluster) region; }]
      ++ (lib.forEach regions (region: {
        inherit region;
        alias = awsProviderNameFor region;
      }));
  };

}
