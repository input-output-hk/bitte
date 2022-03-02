/* Policies
   Related to roles that are impersonated by humans.
   -> Machine roles best have a different venue.
*/
{ terralib, config, lib, ... }:
let

  inherit (terralib) var id;
  inherit (config.cluster) infraType;

  tfcfg = config.tf.hydrate-cluster.configuration;

  __fromTOML = builtins.fromTOML;

  vaultPolicies = tfcfg.locals.policies.vault;
  nomadPolicies = tfcfg.locals.policies.nomad;
  consulPolicies = tfcfg.locals.policies.consul;

  localsBasePolicy = __fromTOML (__readFile ./policies-base.toml);
  localsAwsPolicy = __fromTOML (__readFile ./policies-aws.toml);

  localsPolicy = if infraType == "prem" then localsBasePolicy
                 else lib.recursiveUpdate localsBasePolicy localsAwsPolicy;

in {
  tf.hydrate-cluster.configuration = {

    # this is an auxiliary datastructure that can be modified/extended via terranix's magic merge
    locals.policies = localsPolicy;

    # Vault
    resource.vault_policy = __mapAttrs (name: v: {
      inherit name;
      policy = __toJSON vaultPolicies.${name};
    }) vaultPolicies;

    # Nomad
    resource.nomad_acl_policy = __mapAttrs (name: v: {
      inherit name;
      rules_hcl = __toJSON nomadPolicies.${name};
    }) nomadPolicies;
    # ... also create associated vault roles
    resource.vault_generic_endpoint = __mapAttrs (name: v: {
      path = "nomad/role/${name}";
      ignore_absent_fields = true;
      data_json = __toJSON { policies = [ name ]; };
    }) nomadPolicies;

    # Consul
    resource.consul_acl_policy = __mapAttrs (name: v: {
      inherit name;
      rules = __toJSON consulPolicies.${name};
    }) consulPolicies;
    # ... also create associated consul roles
    resource.consul_acl_role = __mapAttrs (name: v: {
      inherit name;
      policies = [ (id "consul_acl_policy.${name}") ];
    }) consulPolicies;
    # ... also create associated vault consul roles
    resource.vault_consul_secret_backend_role = __mapAttrs (name: v: {
     inherit name;
     backend = "consul";
     policies = [ name ];
    }) consulPolicies;
  };
}
