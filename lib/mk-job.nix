{ config, pkgs, ... }:
let
  inherit (pkgs) toPrettyJSON writeShellScriptBin;
  inherit (config) cluster;
  inherit (cluster) region domain;

  env = ''
    vault login -method aws -no-print

    NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/admin)"
    export NOMAD_TOKEN

    CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/nomad-client)"
    export CONSUL_HTTP_TOKEN

    export AWS_DEFAULT_REGION="${region}"
    export BITTE_CLUSTER="${cluster.name}"
    export AWS_PROFILE=atala
    export VAULT_ADDR="https://vault.${domain}"
    export NOMAD_ADDR="https://nomad.${domain}"
  '';

  upstreams = {
    bitcoind = {
      destinationName = "bitcoind";
      localBindPort = 18333;
    };
    postgres = {
      destinationName = "postgres";
      localBindPort = 5432;
    };
  };

  lcoalhost = "127.0.0.1";

  ecr = "895947072537.dkr.ecr.us-east-2.amazonaws.com";
  tag = "develop-2586-a9d768cf";

  ecrImage = name: "${ecr}/${name}:${tag}";

  jobdef = {
    Name = name;
    id = name;
    Datacenters = [ region ];
    taskGroups = [
      {
        name = "prism";
        networks = [{ mode = "bridge"; }];
        services = [{
          name = "node";
          connect.sidecarService = {
            proxy = {
              upstreams = with upstreams; [ bitcoind postgres ];
              config.protocol = "http";
              localServicePort = 50053;
            };
          };
        }];

        tasks = [{
          node = {
            driver = "docker";
            config.image = ecrImage "node";
            env = {
              GEUD_NODE_PSQL_HOST = "127.0.0.1";
              GEUD_NODE_PSQL_DATABASE = "node";
              GEUD_NODE_PSQL_USERNAME = "node";
              GEUD_NODE_PSQL_PASSWORD = "node";
              GEUD_NODE_BITCOIND_HOST = "127.0.0.1";
              GEUD_NODE_BITCOIND_PORT = upstreams.bitcoind.localBindPort;
              GEUD_NODE_BITCOIND_USERNAME = "bitcoin";
              GEUD_NODE_BITCOIND_PASSWORD = "bitcoin";
            };
          };
        }];
      }

      {
        name = "landing";
        networks = [{ mode = "bridge"; }];

        service = [{
          name = "landing";
          tags = [ "http" ];
          port = "http";

          connect.sidecarService = {
            proxy = {
              config.protocol = "http";
              localServicePort = 80;
            };
          };

          checks = [{
            type = "http";
            path = "/";
            interval = "10s";
            timeout = "1s";
          }];
        }];

        tasks = [{
          landing = {
            driver = "docker";
            config.image = ecrImage "landing";
            env.REACT_APP_GRPC_CLIENT = "https://${domain}:4433";
          };
        }];
      }

      {
        name = "web";
        networks = [{ mode = "bridge"; }];

        services = [{
          name = "web";
          tags = [ "http" ];
          port = "http";

          connect.sidecarService = {
            proxy = {
              config.protocol = "http";
              localServicePort = 80;
            };
          };

          checks = [{
            type = "http";
            path = "/";
            interval = "10s";
            timeout = "1s";
          }];
        }];

        tasks = [{
          web = {
            driver = "docker";
            config.image = ecrImage "web";
            env = {
              REACT_APP_GRPC_CLIENT = "https://${domain}:10000";
              REACT_APP_WALLET_GRPC_CLIENT = "http://${domain}:10000";
              REACT_APP_ISSUER = "c8834532-eade-11e9-a88d-d8f2ca059830";
              REACT_APP_VERIFIER = "f424f42c-2097-4b66-932d-b5e53c734eff";
            };
          };
        }];
      }

      {
        name = "connector";
        networks = [{ mode = "bridge"; }];

        services = [{
          name = "connector";
          connect.sidecarService = {
            proxy = { upstreams = [ upstreams.postgres ]; };
          };
        }];

        task.connector = {
          driver = "docker";
          config.image = ecrImage "connector";

          env = {
            GEUD_CONNECTOR_PSQL_HOST = "127.0.0.1";
            GEUD_CONNECTOR_PSQL_DATABASE = "connector";
            GEUD_CONNECTOR_PSQL_USERNAME = "connector";
            GEUD_CONNECTOR_PSQL_PASSWORD = "connector";
            PRISM_CONNECTOR_NODE_HOST = "127.0.0.1";
            PRISM_CONNECTOR_NODE_PORT = "50053";
          };
        };
      }

      {
        name = "bitcoind";
        networks = [{ mode = "bridge"; }];

        services = [{
          name = "bitcoind";
          port = upstreams.bitcoind.localBindPort;
          connect.sidecarService = [ { } ];
        }];

        tasks = [{
          bitcoind = {
            driver = "docker";

            config = {
              image = "ruimarinho/bitcoin-core";
              auth.server_address = "hub.docker.com:443";

              args = [
                "-printtoconsole"
                "-regtest=1"
                "-rpcallowip=0.0.0.0/0"
                "-rpcuser=bitcoin"
                "-rpcpassword=bitcoin"
                "-rpcbind=0.0.0.0:18333"
              ];
            };
          };
        }];
      }

      {
        name = "db";
        networks = [{ mode = "bridge"; }];

        services = [{
          name = "postgres";
          port = upstreams.postgres.localBindPort;
          connect.sidecarService = [ { } ];
        }];

        tasks = [{
          postgres = {
            driver = "docker";

            env = { POSTGRES_PASSWORD = "postgres"; };

            config = {
              image = "postgres:12";
              auth.server_address = "hub.docker.com:443";
              volumes = let
                pgInit = pkgs.writeTextDir "entrypoint/pg.sql" ''
                  CREATE DATABASE connector;
                  CREATE USER connector WITH ENCRYPTED PASSWORD 'connector';
                  GRANT ALL PRIVILEGES ON DATABASE connector TO connector;

                  CREATE DATABASE node;
                  CREATE USER node WITH ENCRYPTED PASSWORD 'node';
                  GRANT ALL PRIVILEGES ON DATABASE node TO node;

                  CREATE DATABASE demo;
                  CREATE USER demo WITH ENCRYPTED PASSWORD 'demo';
                  GRANT ALL PRIVILEGES ON DATABASE demo TO demo;
                '';
              in [ "${pgInit}/entrypoint:/docker-entrypoint-initdb.d" ];
            };
          };
        }];
      }
    ];
  };

  name = "atala-${tag}";
  jobFile = toPrettyJSON name { Job = jobdef; };
in writeShellScriptBin name ''
  set -euo pipefail

  ${env}

  nomad job run ${jobFile}
''
