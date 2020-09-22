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
      "sys/policies/*".capabilities = [ c r u d l ];
      "sys/policy".capabilities = [ c r u d l ];
      "sys/policy/*".capabilities = [ c r u d l ];
    };

    core.path = {
      "consul/creds/*".capabilities = [ r ];
      "nomad/creds/*".capabilities = [ r ];
      "nomad/config/access".capabilities = [ c u ];
      "kv/data/bootstrap/*".capabilities = [ r ];
      "kv/data/bootstrap/ca".capabilities = [ c r u d l ];

      "auth/token/create".capabilities = [ c r u d l s ];
      "auth/token/create/nomad-server".capabilities = [ u ];
      "auth/token/create/nomad-cluster".capabilities = [ u ];
      "auth/token/create-orphan".capabilities = [ c r u d l ];
      "auth/token/lookup".capabilities = [ u ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "auth/token/revoke-accessor".capabilities = [ u ];
      "auth/token/roles/nomad-server".capabilities = [ r ];
      "auth/token/roles/nomad-cluster".capabilities = [ r ];
      "sys/capabilities-self".capabilities = [ u ];

      "pki/roles/server".capabilities = [ r ];
      "pki/issue/*".capabilities = [ c u ];
      "pki/certs".capabilities = [ l ];
      "pki/revoke".capabilities = [ c u ];
      "pki/tidy".capabilities = [ c u ];
      "pki/cert/ca".capabilities = [ r ];
      "pki-consul/*".capabilities = [ s ];
    };

    # TODO: Pull list from config.cluster.iam

    client.path = {
      "auth/token/create".capabilities = [ u ];
      "auth/token/create/nomad-cluster".capabilities = [ u ];
      "auth/token/create/nomad-server".capabilities = [ u ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "auth/token/roles/nomad-cluster".capabilities = [ r ];
      "auth/token/roles/nomad-server".capabilities = [ r ];
      "consul/creds/consul-agent".capabilities = [ r ];
      "consul/creds/consul-default".capabilities = [ r ];
      "consul/creds/consul-register".capabilities = [ r ];
      "consul/creds/nomad-client".capabilities = [ r ];
      "consul/creds/vault-client".capabilities = [ r ];
      "kv/data/bootstrap/clients/*".capabilities = [ r ];
      "pki/issue/client".capabilities = [ c u ];
      "pki/roles/client".capabilities = [ r ];
      # TODO: add nomad creds here
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
    };
  };
}
