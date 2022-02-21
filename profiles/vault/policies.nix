{ config, lib, ... }:
let
  c = "create";
  r = "read";
  u = "update";
  d = "delete";
  l = "list";
  s = "sudo";

  deployType =
    config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
in {
  services.vault.policies = {
    # Role for prem or premSim
    vault-agent-core = lib.mkIf (deployType != "aws") {
      path = {
        "auth/token/create".capabilities = [ c r u d l s ];
        "consul/creds/nomad-server".capabilities = [ r ];
        "consul/creds/consul-server-default".capabilities = [ r ];
        "consul/creds/consul-server-agent".capabilities = [ r ];
        "nomad/creds/*".capabilities = [ r ];
        "nomad/role/admin".capabilities = [ u ];
        "sys/policies/acl/admin".capabilities = [ u ];
        "sys/storage/raft/snapshot".capabilities = [ r ];
      };
    };

    # Role for prem or premSim
    vault-agent-client = lib.mkIf (deployType != "aws") {
      path = {
        "auth/token/create".capabilities = [ c r u d l s ];
        "consul/creds/consul-agent".capabilities = [ r u ];
        "consul/creds/consul-default".capabilities = [ r u ];
        "kv/data/bootstrap/clients/*".capabilities = [ r ];
        "kv/data/bootstrap/static-tokens/clients/*".capabilities = [ r ];
        "pki/issue/client".capabilities = [ c u ];
        "pki/roles/client".capabilities = [ r ];
      };
    };

    core.path = {
      "auth/token/create".capabilities = [ c r u d l s ];
      "auth/token/create/nomad-cluster".capabilities = [ u ];
      "auth/token/create/nomad-server".capabilities = [ u ];
      "auth/token/create/nomad-autoscaler".capabilities = [ u ];
      "auth/token/create-orphan".capabilities = [ c r u d l ];
      "auth/token/lookup".capabilities = [ u ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "auth/token/revoke-accessor".capabilities = [ u ];
      "auth/token/roles/nomad-cluster".capabilities = [ r ];
      "auth/token/roles/nomad-server".capabilities = [ r ];
      "auth/token/roles/nomad-autoscaler".capabilities = [ r ];
      "consul/creds/consul-register".capabilities = [ r ];
      "consul/creds/consul-server-agent".capabilities = [ r ];
      "consul/creds/consul-server-default".capabilities = [ r ];
      "consul/creds/nomad-autoscaler".capabilities = [ r ];
      "consul/creds/nomad-server".capabilities = [ r ];
      "consul/creds/vault-server".capabilities = [ r ];
      "consul/creds/ingress".capabilities = [ r ];
      "kv/data/bootstrap/ca".capabilities = [ c r u d l ];
      "kv/data/bootstrap/static-tokens/*".capabilities = [ c r u d l ];
      "kv/data/bootstrap/*".capabilities = [ r ];
      "kv/data/bootstrap/letsencrypt/cert".capabilities = [ c r u d l ];
      "kv/data/bootstrap/letsencrypt/fullchain".capabilities = [ c r u d l ];
      "kv/data/bootstrap/letsencrypt/key".capabilities = [ c r u d l ];
      "nomad/config/access".capabilities = [ c u ];
      "nomad/creds/*".capabilities = [ r ];
      "pki/cert/ca".capabilities = [ r ];
      "pki/certs".capabilities = [ l ];
      "pki-consul/*".capabilities = [ s ];
      "pki/issue/*".capabilities = [ c u ];
      "pki/revoke".capabilities = [ c u ];
      "pki/roles/server".capabilities = [ r ];
      "pki/tidy".capabilities = [ c u ];
      "sys/capabilities-self".capabilities = [ u ];
      "sys/storage/raft/snapshot".capabilities = [ r ];
    };

    # TODO: Pull list from config.cluster.iam

    client.path = {
      "auth/token/create".capabilities = [ u s ];
      "auth/token/create/nomad-cluster".capabilities = [ u ];
      "auth/token/create/nomad-server".capabilities = [ u ];
      "auth/token/lookup".capabilities = [ u ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "auth/token/revoke-accessor".capabilities = [ u ];
      "auth/token/roles/nomad-cluster".capabilities = [ r ];
      "auth/token/roles/nomad-server".capabilities = [ r ];
      "consul/creds/consul-agent".capabilities = [ r ];
      "consul/creds/consul-default".capabilities = [ r ];
      "consul/creds/consul-register".capabilities = [ r ];
      "consul/creds/nomad-client".capabilities = [ r ];
      "consul/creds/vault-client".capabilities = [ r ];
      "kv/data/bootstrap/clients/*".capabilities = [ r ];
      "kv/data/bootstrap/static-tokens/clients/*".capabilities = [ r ];
      "kv/data/nomad-cluster/*".capabilities = [ r l ];
      "kv/metadata/nomad-cluster/*".capabilities = [ r l ];
      "pki/issue/client".capabilities = [ c u ];
      "pki/roles/client".capabilities = [ r ];
      "sys/capabilities-self".capabilities = [ u ];
    };

    hydra.path = {
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "consul/creds/consul-default".capabilities = [ r u ];
      "consul/creds/consul-agent".capabilities = [ r u ];
      "consul/creds/traefik".capabilities = [ r u ];
    };

    routing.path = {
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "consul/creds/consul-default".capabilities = [ r u ];
      "consul/creds/consul-agent".capabilities = [ r u ];
      "consul/creds/traefik".capabilities = [ r u ];
    };

    nomad-server.path = {
      # Allow creating tokens under "nomad-cluster" role. The role name should be
      # updated if "nomad-cluster" is not used.
      "auth/token/create/nomad-cluster".capabilities = [ u ];

      # Allow looking up "nomad-cluster" role.
      "auth/token/roles/nomad-cluster".capabilities = [ r ];

      # Allow looking up the token passed to Nomad to validate the token has the
      # proper capabilities. This is provided by the "default" policy.
      "auth/token/lookup-self".capabilities = [ r ];

      # Allow looking up incoming tokens to validate they have permissions to access
      # the tokens they are requesting. This is only required if
      # `allow_unauthenticated` is set to false.
      "auth/token/lookup".capabilities = [ u ];

      # Allow revoking tokens that should no longer exist. This allows revoking
      # tokens for dead tasks.
      "auth/token/revoke-accessor".capabilities = [ u ];

      # Allow checking the capabilities of our own token. This is used to validate the
      # token upon startup.
      "sys/capabilities-self".capabilities = [ u ];

      # Allow our own token to be renewed.
      "auth/token/renew-self".capabilities = [ u ];

      "kv/data/nomad-cluster/*".capabilities = [ r l ];
    };
  };
}
