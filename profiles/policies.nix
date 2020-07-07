{ config, ... }: {
  services.consul = {
    roles = with config.services.consul.policies; {
      consul-agent.policyNames = [ consul-agent.name ];
      consul-server.policyNames = [ consul-agent.name ];
      core-1-consul.policyNames = [ consul-agent.name core-1.name ];
      core-2-consul.policyNames = [ consul-agent.name core-2.name ];
      core-3-consul.policyNames = [ consul-agent.name core-3.name ];
      nomad-client.policyNames = [ nomad-client.name ];
      nomad-server.policyNames = [ nomad-server.name ];
      vault-server.policyNames = [ vault-server.name ];
    };

    policies = let
      read = path: { "${path}".policy = "read"; };
      allRead = read "";
      write = path: { "${path}".policy = "write"; };
      allWrite = write "";
      deny = path: { "${path}".policy = "deny"; };
      allDeny = deny "";
      list = path: { "${path}".policy = "list"; };
      allList = list "";
    in {
      admin = {
        agentPrefix = allWrite;
        eventPrefix = allWrite;
        keyPrefix = allWrite;
        queryPrefix = allWrite;
        servicePrefix = allWrite;
        sessionPrefix = allWrite;

        acl = "write";
        keyring = "write";
        operator = "write";
      };

      core-1.node = write "core-1";
      core-2.node = write "core-2";
      core-3.node = write "core-3";

      dns = {
        nodePrefix = allRead;
        servicePrefix = allRead;
        queryPrefix = allRead;
      };

      consul-agent = {
        nodePrefix = allWrite;
        servicePrefix = allRead;
      };

      consul-default = {
        agentPrefix = allWrite;
        nodePrefix = allWrite;
        servicePrefix = allRead;
      };

      consul-server-default = {
        nodePrefix = allWrite;
        # servicePrefix = allWrite;

        agentPrefix = allWrite;
        eventPrefix = allWrite;
        keyPrefix = allWrite;
        queryPrefix = allWrite;
        servicePrefix = allWrite;
        sessionPrefix = allWrite;

        acl = "write";
        keyring = "write";
        operator = "write";
      };

      consul-server-agent = {
        nodePrefix = allWrite;
        servicePrefix = allRead;
      };

      vault-server = {
        agentPrefix = allWrite;
        keyPrefix = write "vault/";
        nodePrefix = allWrite;
        service = write "vault";
        sessionPrefix = allWrite;
      };

      vault-client = {
        agentPrefix = allWrite;
        keyPrefix = write "vault/";
        nodePrefix = allWrite;
        service = write "vault";
        sessionPrefix = allWrite;
      };

      nomad-server = {
        # agentPrefix = allRead;
        # nodePrefix = allRead;
        # servicePrefix = allWrite;
        # keyPrefix = allWrite;
        # acl = "write";

        agentPrefix = allWrite;
        eventPrefix = allWrite;
        keyPrefix = allWrite;
        queryPrefix = allWrite;
        servicePrefix = allWrite;
        sessionPrefix = allWrite;

        acl = "write";
        keyring = "write";
        operator = "write";
      };

      nomad-client = {
        agentPrefix = allRead;
        nodePrefix = allRead;
        servicePrefix = allWrite;
        keyPrefix = allRead;
      };
    };
  };

  services.vault.policies = let
    c = "create";
    r = "read";
    u = "update";
    d = "delete";
    l = "list";
    s = "sudo";
  in {
    core.path = {
      "consul/creds/*".capabilities = [ r ];
      "nomad/creds/*".capabilities = [ r ];
      "kv/data/bootstrap/*".capabilities = [ r ];

      "auth/token/create/nomad-cluster".capabilities = [ u ];
      "auth/token/roles/nomad-cluster".capabilities = [ r ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "sys/capabilities-self".capabilities = [ u ];
      "auth/token/lookup".capabilities = [ u ];
    };

    # TODO: Pull list from config.cluster.iam

    clients.path = {
      "auth/token/create/nomad-cluster".capabilities = [ u ];
      "auth/token/roles/nomad-cluster".capabilities = [ r ];
      "auth/token/lookup-self".capabilities = [ r ];
      "auth/token/renew-self".capabilities = [ u ];
      "consul/creds/nomad-client".capabilities = [ r ];
      "consul/creds/consul-agent".capabilities = [ r ];
      "consul/creds/consul-default".capabilities = [ r ];
      "consul/creds/vault-client".capabilities = [ r ];
      # TODO: add nomad creds here
    };
  };
}

# nomad = {
#   admin = {
#     description = "Root token (full-access)";
#     namespace."*" = {
#       policy = "write";
#       capabilities = [ "alloc-node-exec" ];
#     };
#     agent.policy = "write";
#     operator.policy = "write";
#     quota.policy = "write";
#     node.policy = "write";
#     host_volume."*".policy = "write";
#   };
#
#   nomad-client = { };
#
#   nomad-server = { };
#
#   anonymous = {
#     description = "Anonymous policy (full-access)";
#
#     namespace."*" = {
#       policy = "write";
#       capabilities = [ "alloc-node-exec" ];
#     };
#     agent.policy = "write";
#     operator.policy = "write";
#     quota.policy = "write";
#     node.policy = "write";
#     host_volume."*".policy = "write";
#   };
# };
