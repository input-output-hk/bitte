job "atala" {
  datacenters = ["eu-central-1"]

  group "prism" {
    network {
      mode = "bridge"
    }

    service {
      name = "node"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "postgres"
              local_bind_port = 5432
            }

            upstreams {
              destination_name = "bitcoind"
              local_bind_port = 18333
            }
          }
        }
      }
    }

    task "node" {
      driver = "docker"

      env {
        GEUD_NODE_PSQL_HOST = "127.0.0.1"
        GEUD_NODE_PSQL_DATABASE = "node"
        GEUD_NODE_PSQL_USERNAME = "node"
        GEUD_NODE_PSQL_PASSWORD = "node"
        GEUD_NODE_BITCOIND_HOST = "127.0.0.1"
        GEUD_NODE_BITCOIND_PORT = 18333
        GEUD_NODE_BITCOIND_USERNAME = "bitcoin"
        GEUD_NODE_BITCOIND_PASSWORD = "bitcoin"
      }

      config = {
        image = "895947072537.dkr.ecr.us-east-2.amazonaws.com/node:develop-2560-c7343da9"
      }
    }
  }

  group "web" {
    network {
      mode = "bridge"
      port "http" { to = 80 }
    }

    service {
      name = "web"
      tags = ["http"]
      port = "http"
      connect { sidecar_service {
        proxy {
          local_service_port = 80
        }
      } }
      check {
        type = "http"
        path = "/"
        interval = "10s"
        timeout = "10s"
      }
    }

    task "web" {
      driver = "docker"

      meta {
        version = 49
      }

      env {
        REACT_APP_GRPC_CLIENT = "https://example.com:10000"
        REACT_APP_WALLET_GRPC_CLIENT = "http://example.com:10000"
        REACT_APP_ISSUER = "c8834532-eade-11e9-a88d-d8f2ca059830"
        REACT_APP_VERIFIER = "f424f42c-2097-4b66-932d-b5e53c734eff"
      }

      config = {
        image = "895947072537.dkr.ecr.us-east-2.amazonaws.com/web:develop-2560-c7343da9"
      }
    }
  }

  group "connector" {
    network {
      mode = "bridge"
    }

    service {
      name = "connector"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "postgres"
              local_bind_port = 5432
            }
          }
        }
      }
    }

    task "connector" {
      driver = "docker"

      env {
        GEUD_CONNECTOR_PSQL_HOST = "127.0.0.1"
        GEUD_CONNECTOR_PSQL_DATABASE = "connector"
        GEUD_CONNECTOR_PSQL_USERNAME = "connector"
        GEUD_CONNECTOR_PSQL_PASSWORD = "connector"
        PRISM_CONNECTOR_NODE_HOST = "127.0.0.1"
        PRISM_CONNECTOR_NODE_PORT = "50053"
      }

      config = {
        image = "895947072537.dkr.ecr.us-east-2.amazonaws.com/connector:develop-2560-c7343da9"
      }
    }
  }

  group "bitcoind" {
    network {
      mode = "bridge"
    }

    service {
      name = "bitcoind"
      port = "18333"

      connect {
        sidecar_service {}
      }
    }

    task "bitcoind" {
      driver = "docker"

      config {
        image = "ruimarinho/bitcoin-core"

        args = [
          "-printtoconsole",
          "-regtest=1",
          "-rpcallowip=0.0.0.0/0",
          "-rpcuser=bitcoin",
          "-rpcpassword=bitcoin",
          "-rpcbind=0.0.0.0:18333"
        ]

        auth {
          server_address = "hub.docker.com:443"
        }
      }
    }
  }

  group "db" {
    network {
      mode = "bridge"
    }

    service {
      name = "postgres"
      port = "5432"

      connect {
        sidecar_service {}
      }
    }

    task "postgres" {
      driver = "docker"

      env {
        POSTGRES_PASSWORD = "postgres"
      }

      config {
        image = "postgres:12"

        volumes = [
          "/tmp/docker-entrypoint:/docker-entrypoint-initdb.d"
        ]

        auth {
          server_address = "hub.docker.com:443"
        }
      }
    }
  }
}
