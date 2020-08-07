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

      "auth/token/create/*".capabilities = [ c r u d l ];
      "auth/token/roles/*".capabilities = [ c r u d l ];
      "auth/token/lookup".capabilities = [ c r u d l ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "sys/capabilities-self".capabilities = [ s ];
      "sys/policy".capabilities = [ c r u d l ];
      "sys/policy/*".capabilities = [ c r u d l ];
      "sys/policies/*".capabilities = [ c r u d l ];
      "identity/*".capabilities = [ c r u d l ];
    };

    core.path = {
      "consul/creds/*".capabilities = [ r ];
      "nomad/creds/*".capabilities = [ r ];
      "nomad/config/access".capabilities = [ c u ];
      "kv/data/bootstrap/*".capabilities = [ r ];
      "kv/data/bootstrap/ca".capabilities = [ c r u d l ];

      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "sys/capabilities-self".capabilities = [ u ];
      "auth/token/lookup".capabilities = [ u ];

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
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "consul/creds/nomad-client".capabilities = [ r ];
      "consul/creds/consul-agent".capabilities = [ r ];
      "consul/creds/consul-default".capabilities = [ r ];
      "consul/creds/vault-client".capabilities = [ r ];
      "consul/creds/consul-register".capabilities = [ r ];
      "pki/roles/client".capabilities = [ r ];
      "pki/issue/client".capabilities = [ c u ];
      "kv/data/bootstrap/*".capabilities = [ r ];
      # TODO: add nomad creds here
    };
  };
}
