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

  tfConfig = { key, extraConfig ? { } }: {
    terraform.backend.http = {
      address = "${vbkStub}/${key}";
      lock_address = "${vbkStub}/${key}";
      unlock_address = "${vbkStub}/${key}";
      skip_cert_verification = vbkBackendSkipCertVerification;
    };
    terraform.required_providers = pkgs.terraform-provider-versions;
    provider.vault = { };
  } // extraConfig;

in {
  # preconfigure hydrate-secrets
  tf.hydrate-secrets.configuration = tfConfig { key = "hydrate-secrets"; };

  # preconfigure hydrate-app
  tf.hydrate-app.configuration = tfConfig { key = "hydrate-app"; };

  # preconfigure hydrate-cluster
  tf.hydrate-cluster.configuration = tfConfig {
    key = "hydrate-cluster";
    extraConfig = {
      provider.aws = [{ inherit (config.cluster) region; }]
        ++ (lib.forEach regions (region: {
          inherit region;
          alias = awsProviderNameFor region;
        }));
    };
  };
}
