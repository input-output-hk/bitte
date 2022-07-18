{
  config,
  lib,
  ...
}: {
  services.consul = {
    roles = with config.services.consul.policies; {
      consul-agent.policyNames = [consul-agent.name];
      consul-server.policyNames = [consul-agent.name];
      nomad-server.policyNames = [nomad-server.name];
      vault-server.policyNames = [vault-server.name];
    };

    policies = let
      allDeny = deny "";
      allList = list "";
      allRead = read "";
      allWrite = write "";
      deny = path: {"${path}".policy = "deny";};
      list = path: {"${path}".policy = "list";};
      read = path: {"${path}".policy = "read";};
      write = path: {"${path}".policy = "write";};
    in {
      dns = {
        nodePrefix = allRead;
        servicePrefix = allRead;
        queryPrefix = allRead;
      };

      consul-agent = {
        nodePrefix = allWrite;
        servicePrefix = allRead;
      };

      # Shared between Consul and Nomad, due to inability of Nomad to reload tokens.
      # Intentions read ACL now required for connect on the default token.
      consul-default = {
        agentPrefix = allWrite;
        nodePrefix = allWrite;
        servicePrefix."" = {
          policy = "write";
          intentions = "read";
        };
        keyPrefix = allRead;
      };

      traefik = {
        servicePrefix = allRead;
        nodePrefix = allRead;
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

      consul-register = {
        nodePrefix = allWrite;
        servicePrefix = allWrite;
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
        agentPrefix = allRead;
        nodePrefix = allRead;
        servicePrefix = allWrite;
        keyPrefix = allWrite;
        acl = "write";
      };
    };
  };
}
