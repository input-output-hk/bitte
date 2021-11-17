{ config, pkgs, ... }:
let
  inherit (pkgs) writeShellScriptBin mkNomadJob;
  inherit (config) cluster;
  inherit (cluster) region domain;

  ecr = "895947072537.dkr.ecr.us-east-2.amazonaws.com";
  tag = "develop-2598-1980ac7a";

  ecrImage = imageName: "${ecr}/${imageName}:${tag}";

  name = "atala-${tag}";

  jobdef = mkNomadJob name {
    datacenters = [ region ];

    update = {
      maxParallel = 1;
      healthCheck = "checks";
      minHealthyTime = "10s";
      healthyDeadline = "5m";
      progressDeadline = "10m";
      autoRevert = true;
      autoPromote = true;
      canary = 1;
      stagger = "30s";
    };

    taskGroups = {
      "prism-${tag}" = {
        services."node-${tag}" = {
          connect.sidecarService = {
            proxy = {
              upstreams = [
                {
                  destinationName = "postgres-${tag}";
                  localBindPort = 5432;
                }
                {
                  destinationName = "bitcoind-${tag}";
                  localBindPort = 18333;
                }
              ];
            };
          };
        };

        tasks."node-${tag}" = {
          driver = "docker";

          env = {
            GEUD_NODE_PSQL_HOST = "127.0.0.1";
            GEUD_NODE_PSQL_DATABASE = "node";
            GEUD_NODE_PSQL_USERNAME = "node";
            GEUD_NODE_PSQL_PASSWORD = "node";
            GEUD_NODE_BITCOIND_HOST = "127.0.0.1";
            GEUD_NODE_BITCOIND_PORT = toString 18333;
            GEUD_NODE_BITCOIND_USERNAME = "bitcoin";
            GEUD_NODE_BITCOIND_PASSWORD = "bitcoin";
          };

          config.image = ecrImage "node";
        };
      };

      "landing-${tag}" = {
        count = 1;
        update.maxParallel = 1;

        services."landing-${tag}" = {
          portLabel = "80";
          connect.sidecarService = { };
        };

        tasks."landing-${tag}" = {
          driver = "docker";

          resources = {
            cpu = 20;
            memoryMB = 15;
          };

          env = {
            REACT_APP_GRPC_CLIENT = "https://connector.${domain}:4422";
            REACT_APP_WALLET_GRPC_CLIENT = "https://connector.${domain}:4422";
            REACT_APP_ISSUER = "c8834532-eade-11e9-a88d-d8f2ca059830";
            REACT_APP_VERIFIER = "f424f42c-2097-4b66-932d-b5e53c734eff";
          };

          config.image = ecrImage "landing";
        };
      };

      "web-${tag}" = {
        services."web-${tag}" = {
          portLabel = "80";
          connect.sidecarService = { };
        };

        tasks."web-${tag}" = {
          driver = "docker";

          resources = {
            cpu = 20;
            memoryMB = 15;
          };

          env = {
            REACT_APP_GRPC_CLIENT = "https://connector.${domain}:4422";
            REACT_APP_WALLET_GRPC_CLIENT = "https://connector.${domain}:4422";
            REACT_APP_ISSUER = "c8834532-eade-11e9-a88d-d8f2ca059830";
            REACT_APP_VERIFIER = "f424f42c-2097-4b66-932d-b5e53c734eff";
          };

          config.image = ecrImage "web";
        };
      };

      "connector-${tag}" = {
        services."connector-${tag}" = {
          portLabel = "50051";
          connect.sidecarService.proxy = {
            config.protocol = "grpc";
            upstreams = [{
              destinationName = "postgres-${tag}";
              localBindPort = 5432;
            }];
          };
        };

        tasks."connector-${tag}" = {
          driver = "docker";

          resources = {
            cpu = 20;
            memoryMB = 260;
          };

          env = {
            GEUD_CONNECTOR_PSQL_HOST = "127.0.0.1";
            GEUD_CONNECTOR_PSQL_DATABASE = "connector";
            GEUD_CONNECTOR_PSQL_USERNAME = "connector";
            GEUD_CONNECTOR_PSQL_PASSWORD = "connector";
            PRISM_CONNECTOR_NODE_HOST = "127.0.0.1";
            PRISM_CONNECTOR_NODE_PORT = "50053";
          };

          config.image = ecrImage "connector";
        };
      };

      "bitcoind-${tag}" = {
        count = 1;

        services."bitcoind-${tag}" = {
          portLabel = "18333";
          connect.sidecarService = { };
        };

        tasks."bitcoind-${tag}" = {
          driver = "docker";

          resources = {
            cpu = 20;
            memoryMB = 140;
          };

          config = {
            image = "ruimarinho/bitcoin-core";

            args = [
              "-printtoconsole"
              "-regtest=1"
              "-rpcallowip=0.0.0.0/0"
              "-rpcuser=bitcoin"
              "-rpcpassword=bitcoin"
              "-rpcbind=0.0.0.0:18333"
            ];

            auth.server_address = "hub.docker.com:443";
          };
        };
      };

      "postgres-${tag}" = {
        update.maxParallel = 1;

        services."postgres-${tag}" = {
          portLabel = "5432";

          connect.sidecarService = { };
        };

        tasks."postgres-${tag}" = {
          driver = "docker";

          env = { POSTGRES_PASSWORD = "postgres"; };

          config = {
            image = "postgres:12";

            volumes = [ "/etc/docker-mounts/db:/docker-entrypoint-initdb.d" ];

            auth.server_address = "hub.docker.com:443";
          };
        };
      };
    };
  };

  jobFile = jobdef.json;
in
{
  job = jobdef.json;
  run = writeShellScriptBin name ''
    set -euo pipefail

    vault login -method aws -no-print

    NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/admin)"
    export NOMAD_TOKEN

    CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/admin)"
    export CONSUL_HTTP_TOKEN

    export AWS_DEFAULT_REGION="${region}"
    export BITTE_CLUSTER="${cluster.name}"
    export AWS_PROFILE=atala
    export VAULT_ADDR="https://vault.${domain}"
    export NOMAD_ADDR="https://nomad.${domain}"

    jq --arg token "$CONSUL_HTTP_TOKEN" '.Job.ConsulToken = $token' < ${jobFile} \
    | curl -f \
        -X POST \
        -H "X-Nomad-Token: $NOMAD_TOKEN" \
        -d @- \
        "$NOMAD_ADDR/v1/jobs"
  '';
}
