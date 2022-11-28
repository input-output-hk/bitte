/*
Policies
Related to roles that are impersonated by humans.
-> Machine roles best have a different venue.
*/
{
  terralib,
  config,
  lib,
  ...
}: let
  inherit (terralib) var id;
  inherit (config.cluster) infraType;

  tfcfg = config.tf.hydrate-cluster.configuration;

  __fromTOML = builtins.fromTOML;

  # necessary or some of these policies get deleted by terraform; eg routing
  coreVaultPolicies =
    builtins.removeAttrs
    (import ../../../profiles/vault/policies.nix {inherit config lib;})
    .services
    .vault
    .policies ["vault-agent-client" "vault-agent-core"];

  vaultPolicies = coreVaultPolicies // tfcfg.locals.policies.vault;
  nomadPolicies = tfcfg.locals.policies.nomad;
  consulPolicies = tfcfg.locals.policies.consul;

  localsBasePolicy = __fromTOML (__readFile ./policies-base.toml);
  localsAwsPolicy = __fromTOML (__readFile ./policies-aws.toml);

  localsPolicy =
    if infraType == "prem"
    then localsBasePolicy
    else lib.recursiveUpdate localsBasePolicy localsAwsPolicy;
in {
  tf.hydrate-cluster.configuration = {
    # this is an auxiliary datastructure that can be modified/extended via terranix's magic merge
    locals.policies = localsPolicy;

    # Vault
    resource.vault_policy =
      __mapAttrs (name: _: {
        inherit name;
        policy = __toJSON (
          lib.recursiveUpdate vaultPolicies.${name}
          # ... also add pki role policies to obtain a workload identity
          {
            path."pki/issue/${name}".capabilities = ["update"];
            path."pki/roles/${name}".capabilities = ["read"];
          }
        );
      })
      vaultPolicies;

    # Nomad
    resource.nomad_acl_policy =
      __mapAttrs (name: v: {
        inherit name;
        rules_hcl = __toJSON nomadPolicies.${name};
      })
      nomadPolicies;

    # ... also create associated vault roles
    resource.vault_generic_endpoint =
      __mapAttrs (name: v: {
        path = "nomad/role/${name}";
        ignore_absent_fields = true;
        data_json = __toJSON {policies = [name];};
      })
      nomadPolicies;

    # Consul
    resource.consul_acl_policy =
      __mapAttrs (name: v: {
        inherit name;
        rules = __toJSON (builtins.removeAttrs consulPolicies.${name} ["vaultConsulSecretBackendRole"]);
      })
      consulPolicies;

    # ... also create associated consul roles
    resource.consul_acl_role =
      __mapAttrs (name: v: {
        inherit name;
        policies = [(id "consul_acl_policy.${name}")];
      })
      consulPolicies;

    # ... also create associated vault consul roles
    resource.vault_consul_secret_backend_role = __mapAttrs (name: v:
      {
        inherit name;
        backend = "consul";

        # Move from a default token ttl and max_ttl of 32 days via vault system max_ttl_lease to 12 day default.
        # This allows for a tighter feedback loop on application token rotation, but still also allows
        # 2 - 3 days lag between attempted rotation at 75 - 80% TTL utilization and token expiration,
        # which will prevent rotation attempts failing on a Friday evening from having an impact until
        # working hours Monday.
        #
        # Ttl remains matched to max_ttl so that scripts handling token rotation do not need to add
        # additional renewal logic complexity.
        ttl = toString (12 * 86400);
        max_ttl = toString (12 * 86400);
        policies = [name];

        # Allow a per policy vault role attribute override.
        # Example: extra short ttl for fast app rotation testing could customize ttl and max_ttl
        # in the hydration profile with:
        #
        #   locals.policies.consul.$ROLENAME.vaultConsulSecretBackendRole = {
        #     ttl = "$EXAMPLE_SECS";
        #     max_ttl = "$EXAMPLE_SECS";
        #   };
        #
      }
      // (v.vaultConsulSecretBackendRole or {}))
    consulPolicies;

    # PKI for vault and consul roles
    resource.vault_pki_secret_backend_role = __mapAttrs (name: _: {
      # TODO: see TODO in ./vault-pki.nix
      # backend = var "vault_pki_secret_backend.pki.path";
      inherit name;
      backend = "pki";
      key_type = "ec";
      key_bits = 256;
      allow_any_name = true;
      enforce_hostnames = false;
      generate_lease = true;
      key_usage = ["DigitalSignature" "KeyAgreement" "KeyEncipherment"];
      # 87600h
      max_ttl = "315360000";
    }) (consulPolicies // vaultPolicies); # we'r only interested in the keys anyway
  };
}
