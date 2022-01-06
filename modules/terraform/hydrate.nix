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
  tf.secrets-hydrate.configuration = abort ''

    secrets-hydrate had been renamed to hydrate-secrets
    please rename your infra cluster tf vault backend accordingly
    and switch!


    VAULT_ADDR=https://vault.infra.aws.iohkdev.io
    VAULT_TOKEN=$TF_HTTP_PASSWORD
    vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-secrets @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/secrets-hydrate | jq .data.data)
  '';
  tf.hydrate-secrets.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/hydrate-secrets";
      lock_address = "${vbkStub}/hydrate-secrets";
      unlock_address = "${vbkStub}/hydrate-secrets";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  };

  # preconfigure hydrate-app
  tf.app-hydrate.configuration = abort ''

    app-hydrate had been renamed to hydrate-app
    please rename your infra cluster tf vault backend accordingly
    and switch!


    VAULT_ADDR=https://vault.infra.aws.iohkdev.io
    VAULT_TOKEN=$TF_HTTP_PASSWORD
    vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-app @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/app-hydrate | jq .data.data)
  '';
  tf.hydrate-app.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/hydrate-app";
      lock_address = "${vbkStub}/hydrate-app";
      unlock_address = "${vbkStub}/hydrate-app";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  };

  # preconfigure hydrate-cluster
  tf.hydrate.configuration = abort ''

    hydrate had been renamed to hydrate-cluster
    please rename your infra cluster tf vault backend accordingly
    and switch!


    VAULT_ADDR=https://vault.infra.aws.iohkdev.io
    VAULT_TOKEN=$TF_HTTP_PASSWORD
    vault kv put secret/vbk/$BITTE_CLUSTER/hydrate-cluster @<(vault kv get -format=json secret/vbk/$BITTE_CLUSTER/hydrate | jq .data.data)
  '';
  tf.hydrate-cluster.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/hydrate-cluster";
      lock_address = "${vbkStub}/hydrate-cluster";
      unlock_address = "${vbkStub}/hydrate-cluster";
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
