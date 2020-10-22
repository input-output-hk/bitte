{ config, ... }:
let
  c = "create";
  r = "read";
  u = "update";
  d = "delete";
  l = "list";
  s = "sudo";
in {
  services.vault.policies = {
    admin.path = {
      "approle/*".capabilities = [ c r u d l ];
      "aws/*".capabilities = [ c r u d l ];
      "consul/*".capabilities = [ c r u d l ];
      "kv/*".capabilities = [ c r u d l ];
      "nomad/*".capabilities = [ c r u d l ];
      "pki/*".capabilities = [ c r u d l ];

      "auth/github-employees/config".capabilities = [ c r u d l s ];
      "auth/github-employees/map/teams/*".capabilities = [ c r u d l s ];
      "auth/token/create".capabilities = [ c r u d l s ];
      "auth/token/create/*".capabilities = [ c r u d l ];
      "auth/token/create/nomad-cluster".capabilities = [ c r u d l s ];
      "auth/token/create/nomad-server".capabilities = [ c r u d l s ];
      "auth/token/roles/nomad-server".capabilities = [ r ];
      "auth/token/create-orphan".capabilities = [ c r u d l ];
      "auth/token/lookup".capabilities = [ c r u d l ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "auth/token/revoke-accessor".capabilities = [ u ];
      "auth/token/roles/*".capabilities = [ c r u d l ];
      "auth/token/roles/nomad-cluster".capabilities = [ c r u d l ];
      "identity/*".capabilities = [ c r u d l ];
      "sys/capabilities-self".capabilities = [ s ];
      "sys/mounts/auth/*".capabilities = [ c r u d l s ];
      "sys/policies/*".capabilities = [ c r u d l ];
      "sys/policy".capabilities = [ c r u d l ];
      "sys/policy/*".capabilities = [ c r u d l ];
      "sys/auth/aws".capabilities = [ c r u d l s ];
      "sys/auth/github-employees".capabilities = [ c r u d l s ];
      "sys/auth/github-employees/config".capabilities = [ c r ];
      "sys/auth".capabilities = [ r l ];
      "auth/aws/role/*".capabilities = [ c r u d l ];
      "auth/aws/config/client".capabilities = [ c r u d l ];
    };

    developer.path = {
      # Allow all KV access
      "kv/*".capabilities = [ c r u d l ];
      # Allow creating AWS tokens
      "aws/creds/developer".capabilities = [ r u ];
      # Allow creating Nomad tokens
      "nomad/creds/developer".capabilities = [ r u ];
      # Allow creating Consul tokens
      "consul/creds/developer".capabilities = [ r u ];
      # Allow lookup of own capabilities
      "sys/capabilities-self".capabilities = [ u ];
      # Allow lookup of own tokens
      "auth/token/lookup-self".capabilities = [ r ];
      # Allow self renewing tokens
      "auth/token/renew-self".capabilities = [ u ];
    };

    core.path = {
      "auth/token/create".capabilities = [ c r u d l s ];
      "auth/token/create/nomad-cluster".capabilities = [ u ];
      "auth/token/create/nomad-server".capabilities = [ u ];
      "auth/token/create-orphan".capabilities = [ c r u d l ];
      "auth/token/lookup".capabilities = [ u ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "auth/token/revoke-accessor".capabilities = [ u ];
      "auth/token/roles/nomad-cluster".capabilities = [ r ];
      "auth/token/roles/nomad-server".capabilities = [ r ];
      "consul/creds/consul-server-agent".capabilities = [ r ];
      "consul/creds/consul-server-default".capabilities = [ r ];
      "consul/creds/nomad-server".capabilities = [ r ];
      "consul/creds/vault-server".capabilities = [ r ];
      "consul/creds/ingress".capabilities = [ r ];
      "kv/data/bootstrap/ca".capabilities = [ c r u d l ];
      "kv/data/bootstrap/*".capabilities = [ r ];
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
      "kv/data/nomad-cluster/*".capabilities = [ r l ];
      "pki/issue/client".capabilities = [ c u ];
      "pki/roles/client".capabilities = [ r ];
      "sys/capabilities-self".capabilities = [ u ];
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

    nomad-cluster.path = {
      "kv/data/nomad-cluster/*".capabilities = [ r l ];
      "auth/token/renew-self".capabilities = [ u ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/lookup".capabilities = [ u ];
    };
  };
}
