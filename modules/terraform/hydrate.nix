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

  # preconfigure secrets-hydrate
  tf.secrets-hydrate.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/secrets-hydrate";
      lock_address = "${vbkStub}/secrets-hydrate";
      unlock_address = "${vbkStub}/secrets-hydrate";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  };

  # preconfigure app-hydrate
  tf.app-hydrate.configuration = {
    terraform.backend.http = {
      address = "${vbkStub}/app-hydrate";
      lock_address = "${vbkStub}/app-hydrate";
      unlock_address = "${vbkStub}/app-hydrate";
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  };

  # preconfigure (cluster-)hydrate
  tf.hydrate.configuration = {
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
