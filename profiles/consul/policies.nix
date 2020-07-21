{ config, ... }: {
  services.consul = {
    intentions = [
      {
        SourceName = "connector";
        DestinationName = "node";
      }
      {
        SourceName = "connector";
        DestinationName = "postgres";
      }
      {
        SourceName = "count-dashboard";
        DestinationName = "count-api";
      }
      {
        SourceName = "haproxy";
        DestinationName = "connector";
      }
      {
        SourceName = "haproxy";
        DestinationName = "landing";
      }
      {
        SourceName = "haproxy";
        DestinationName = "web";
      }
      {
        SourceName = "node";
        DestinationName = "bitcoind";
      }
      {
        SourceName = "node";
        DestinationName = "postgres";
      }
    ];

    roles = with config.services.consul.policies; {
      consul-agent.policyNames = [ consul-agent.name ];
      consul-server.policyNames = [ consul-agent.name ];
      nomad-client.policyNames = [ nomad-client.name ];
      nomad-server.policyNames = [ nomad-server.name ];
      vault-server.policyNames = [ vault-server.name ];
    };

    policies = let
      allDeny = deny "";
      allList = list "";
      allRead = read "";
      allWrite = write "";
      deny = path: { "${path}".policy = "deny"; };
      list = path: { "${path}".policy = "list"; };
      read = path: { "${path}".policy = "read"; };
      write = path: { "${path}".policy = "write"; };
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
        agentPrefix = allRead;
        nodePrefix = allRead;
        servicePrefix = allWrite;
        keyPrefix = allWrite;
        acl = "write";
      };

      nomad-client = {
        agentPrefix = allRead;
        nodePrefix = allRead;
        servicePrefix = allWrite;
        keyPrefix = allRead;
      };
    };
  };
}
