{ config, lib, ... }:
let
  c = "create";
  r = "read";
  u = "update";
  d = "delete";
  l = "list";
  s = "sudo";

  caps = lib.mapAttrs (n: v: { capabilities = v; });

  deployType =
    config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
in {
  services.vault.policies = {
    # Role for prem or premSim
    vault-agent-core = lib.mkIf (deployType != "aws") {
      path = caps {
        "auth/token/create" = [ c r u d l s ];
        "consul/creds/nomad-server" = [ r ];
        "consul/creds/consul-server-default" = [ r ];
        "consul/creds/consul-server-agent" = [ r ];
        "kv/data/system/alerts/*" = [ r ];
        "kv/metadata/system/alerts/*" = [ l ];
        "kv/data/system/dashboards/*" = [ r ];
        "kv/metadata/system/dashboards/*" = [ l ];
        "nomad/creds/*" = [ r ];
        "nomad/role/admin" = [ u ];
        "sys/policies/acl/admin" = [ u ];
        "sys/storage/raft/snapshot" = [ r ];
      };
    };

    # Role for prem or premSim
    vault-agent-client = lib.mkIf (deployType != "aws") {
      path = caps {
        "auth/token/create" = [ c r u d l s ];
        "consul/creds/consul-agent" = [ r u ];
        "consul/creds/consul-default" = [ r u ];
        "kv/data/bootstrap/clients/*" = [ r ];
        "kv/data/bootstrap/static-tokens/clients/*" = [ r ];
        "pki/issue/client" = [ c u ];
        "pki/roles/client" = [ r ];
      };
    };

    core.path = caps {
      "auth/token/create" = [ c r u d l s ];
      "auth/token/create/nomad-cluster" = [ u ];
      "auth/token/create/nomad-server" = [ u ];
      "auth/token/create/nomad-autoscaler" = [ u ];
      "auth/token/create-orphan" = [ c r u d l ];
      "auth/token/lookup" = [ u ];
      "auth/token/lookup-self" = [ r ];
      "auth/token/renew-self" = [ u ];
      "auth/token/revoke-accessor" = [ u ];
      "auth/token/roles/nomad-cluster" = [ r ];
      "auth/token/roles/nomad-server" = [ r ];
      "auth/token/roles/nomad-autoscaler" = [ r ];
      "consul/creds/consul-register" = [ r ];
      "consul/creds/consul-server-agent" = [ r ];
      "consul/creds/consul-server-default" = [ r ];
      "consul/creds/nomad-autoscaler" = [ r ];
      "consul/creds/nomad-server" = [ r ];
      "consul/creds/vault-server" = [ r ];
      "consul/creds/ingress" = [ r ];
      "kv/data/system/alerts/*" = [ r ];
      "kv/metadata/system/alerts/*" = [ l ];
      "kv/data/system/dashboards/*" = [ r ];
      "kv/metadata/system/dashboards/*" = [ l ];
      "kv/data/bootstrap/ca" = [ c r u d l ];
      "kv/data/bootstrap/static-tokens/*" = [ c r u d l ];
      "kv/data/bootstrap/*" = [ r ];
      "kv/data/bootstrap/letsencrypt/cert" = [ c r u d l ];
      "kv/data/bootstrap/letsencrypt/fullchain" = [ c r u d l ];
      "kv/data/bootstrap/letsencrypt/key" = [ c r u d l ];
      "nomad/config/access" = [ c u ];
      "nomad/creds/*" = [ r ];
      "pki/cert/ca" = [ r ];
      "pki/certs" = [ l ];
      "pki/issue/*" = [ c u ];
      "pki/revoke" = [ c u ];
      "pki/roles/server" = [ r ];
      "pki/tidy" = [ c u ];
      "sys/capabilities-self" = [ u ];
      "sys/storage/raft/snapshot" = [ r ];
    };

    # TODO: Pull list from config.cluster.iam

    client.path = caps {
      "auth/token/create" = [ u s ];
      "auth/token/create/nomad-cluster" = [ u ];
      "auth/token/create/nomad-server" = [ u ];
      "auth/token/lookup" = [ u ];
      "auth/token/lookup-self" = [ r ];
      "auth/token/renew-self" = [ u ];
      "auth/token/revoke-accessor" = [ u ];
      "auth/token/roles/nomad-cluster" = [ r ];
      "auth/token/roles/nomad-server" = [ r ];
      "consul/creds/consul-agent" = [ r ];
      "consul/creds/consul-default" = [ r ];
      "consul/creds/consul-register" = [ r ];
      "consul/creds/nomad-client" = [ r ];
      "consul/creds/vault-client" = [ r ];
      "kv/data/bootstrap/clients/*" = [ r ];
      "kv/data/bootstrap/static-tokens/clients/*" = [ r ];
      "kv/data/nomad-cluster/*" = [ r l ];
      "kv/metadata/nomad-cluster/*" = [ r l ];
      "nomad/creds/nomad-follower" = [ r u ];
      "pki/issue/client" = [ c u ];
      "pki/roles/client" = [ r ];
      "sys/capabilities-self" = [ u ];
    };

    hydra.path = caps {
      "auth/token/lookup-self" = [ r ];
      "auth/token/renew-self" = [ u ];
      "consul/creds/consul-default" = [ r u ];
      "consul/creds/consul-agent" = [ r u ];
      "consul/creds/consul-register" = [ r ];
    };

    routing.path = caps {
      "auth/token/lookup-self" = [ r ];
      "auth/token/renew-self" = [ u ];
      "consul/creds/consul-default" = [ r u ];
      "consul/creds/consul-agent" = [ r u ];
      "consul/creds/traefik" = [ r u ];
      "kv/data/bootstrap/letsencrypt/cert" = [ c r u d l ];
      "kv/data/bootstrap/letsencrypt/fullchain" = [ c r u d l ];
      "kv/data/bootstrap/letsencrypt/key" = [ c r u d l ];
    };

    nomad-server.path = caps {
      # Allow creating tokens under "nomad-cluster" role. The role name should be
      # updated if "nomad-cluster" is not used.
      "auth/token/create/nomad-cluster" = [ u ];

      # Allow looking up "nomad-cluster" role.
      "auth/token/roles/nomad-cluster" = [ r ];

      # Allow looking up the token passed to Nomad to validate the token has the
      # proper capabilities. This is provided by the "default" policy.
      "auth/token/lookup-self" = [ r ];

      # Allow looking up incoming tokens to validate they have permissions to access
      # the tokens they are requesting. This is only required if
      # `allow_unauthenticated` is set to false.
      "auth/token/lookup" = [ u ];

      # Allow revoking tokens that should no longer exist. This allows revoking
      # tokens for dead tasks.
      "auth/token/revoke-accessor" = [ u ];

      # Allow checking the capabilities of our own token. This is used to validate the
      # token upon startup.
      "sys/capabilities-self" = [ u ];

      # Allow our own token to be renewed.
      "auth/token/renew-self" = [ u ];

      "kv/data/nomad-cluster/*" = [ r l ];
    };
  };
}
