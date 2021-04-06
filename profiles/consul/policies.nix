{ config, lib, ... }: {
  services.consul = {
    intentions = lib.flatten (lib.mapAttrsToList (source: destinations:
      lib.forEach destinations (destination: {
        sourceName = source;
        destinationName = destination;
      })) {
        connector = [ "node" "postgres" ];
        ingress = [
          "connector"
          "web"
          "landing"
          "connector-develop-2598-1980ac7a"
          "web-develop-2598-1980ac7a"
          "landing-develop-2598-1980ac7a"
        ];
        node = [ "bitcoind" "postgres" ];
        count-dashboard = [ "count-api" ];
        connector-develop-2598-1980ac7a =
          [ "node-develop-2598-1980ac7a" "postgres-develop-2598-1980ac7a" ];
        node-develop-2598-1980ac7a =
          [ "bitcoind-develop-2598-1980ac7a" "postgres-develop-2598-1980ac7a" ];
      });

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
        nodePrefix = allWrite;
        queryPrefix = allWrite;
        servicePrefix = {
          "" = {
            policy = "write";
            intentions = "write";
          };
        };
        sessionPrefix = allWrite;

        acl = "write";
        keyring = "write";
        operator = "write";
      };

      developer = {
        agentPrefix = allRead;
        eventPrefix = allRead;
        keyPrefix = allRead;
        nodePrefix = allRead;
        queryPrefix = allRead;
        servicePrefix = {
          "" = {
            policy = "read";
            intentions = "read";
          };
        };
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

      # Shared between Consul and Nomad, due to inability of Nomad to reload
      # tokens.
      consul-default = {
        agentPrefix = allWrite;
        nodePrefix = allWrite;
        servicePrefix = allWrite;
        keyPrefix = allRead;
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

      # Not used anymore...
      nomad-client = {
        agentPrefix = allRead;
        nodePrefix = allRead;
        servicePrefix = allWrite;
        keyPrefix = allRead;
      };

      # Not used anymore...
      ingress = {
        nodePrefix = allRead;
        servicePrefix = allRead;
        queryPrefix = allRead;
      };
    };
  };
}
