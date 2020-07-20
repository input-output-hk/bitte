job "atala" {
  datacenters = ["eu-central-1"]

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "10s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
    auto_promote      = true
    canary            = 1
    stagger           = "30s"
  }

  group "prism" {
    count = 1

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
        image = "895947072537.dkr.ecr.us-east-2.amazonaws.com/node:develop-2595-d90c64fd"
      }
    }
  }

  group "landing" {
    count = 1

    update {
      max_parallel = 1
    }

    network {
      mode = "bridge"
    }

    service {
      name = "landing"
      port = "80"

      connect {
        sidecar_service {}
      }
    }

    task "landing" {
      driver = "docker"

      resources {
        cpu = 20
        memory = 15
      }

      env {
        REACT_APP_GRPC_CLIENT = "https://connector.testnet.atalaprism.io:4422"
        REACT_APP_WALLET_GRPC_CLIENT = "https://connector.testnet.atalaprism.io:4422"
        REACT_APP_ISSUER = "c8834532-eade-11e9-a88d-d8f2ca059830"
        REACT_APP_VERIFIER = "f424f42c-2097-4b66-932d-b5e53c734eff"
      }

      config = {
        image = "895947072537.dkr.ecr.us-east-2.amazonaws.com/landing:develop-2595-d90c64fd"
      }
    }
  }


  group "web" {
    count = 1

    network {
      mode = "bridge"
    }

    service {
      name = "web"
      port = "80"

      connect {
        sidecar_service { }
      }
    }

    task "web" {
      driver = "docker"

      resources {
        cpu = 20
        memory = 15
      }

      env {
        REACT_APP_GRPC_CLIENT = "https://connector.testnet.atalaprism.io:4422"
        REACT_APP_WALLET_GRPC_CLIENT = "https://connector.testnet.atalaprism.io:4422"
        REACT_APP_ISSUER = "c8834532-eade-11e9-a88d-d8f2ca059830"
        REACT_APP_VERIFIER = "f424f42c-2097-4b66-932d-b5e53c734eff"
      }

      config = {
        image = "895947072537.dkr.ecr.us-east-2.amazonaws.com/web:develop-2595-d90c64fd"
      }
    }
  }

  group "connector" {
    count = 1

    update {
      max_parallel = 1
    }

    network {
      mode = "bridge"
    }

    service {
      name = "connector"
      port = "50051"

      connect {
        sidecar_service {
          proxy {
            config {
              protocol = "grpc"
            }

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

      resources {
        cpu = 20
        memory = 260
      }

      env {
        GEUD_CONNECTOR_PSQL_HOST = "127.0.0.1"
        GEUD_CONNECTOR_PSQL_DATABASE = "connector"
        GEUD_CONNECTOR_PSQL_USERNAME = "connector"
        GEUD_CONNECTOR_PSQL_PASSWORD = "connector"
        PRISM_CONNECTOR_NODE_HOST = "127.0.0.1"
        PRISM_CONNECTOR_NODE_PORT = "50053"
      }

      config = {
        image = "895947072537.dkr.ecr.us-east-2.amazonaws.com/connector:develop-2595-d90c64fd"
      }
    }
  }

  group "bitcoind" {
    count = 1

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

      resources {
        cpu = 20
        memory = 140
      }

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
    update {
      max_parallel = 1
    }

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
          "/etc/docker-mounts/db:/docker-entrypoint-initdb.d"
        ]

        auth {
          server_address = "hub.docker.com:443"
        }
      }
    }
  }
}