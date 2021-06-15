{ lib, pkgs, config, nodeName, ... }:
let inherit (config.cluster) name region domain kms instances;
in {
  environment.variables = {
    NOMAD_ADDR =
      "https://127.0.0.1:${toString config.services.nomad.ports.http}";
  };

  age.secrets = {
    nomad-ca = {
      file = ../../encrypted/ssl/ca.age;
      path = "/var/lib/nomad/ca.pem";
    };

    nomad-client = {
      file = ../../encrypted/ssl/client.age;
      path = "/var/lib/nomad/client.pem";
    };

    nomad-client-key = {
      file = ../../encrypted/ssl/client-key.age;
      path = "/var/lib/nomad/client-key.pem";
    };

    nomad-full = {
      file = ../../encrypted/ssl/server-full.age;
      path = "/var/lib/nomad/full.pem";
    };

    nomad-server = {
      file = ../../encrypted/ssl/server.age;
      path = "/var/lib/nomad/server.pem";
    };

    nomad-server-key = {
      file = ../../encrypted/ssl/server-key.age;
      path = "/var/lib/nomad/server-key.pem";
    };
  };

  services.nomad = {
    data_dir = /var/lib/nomad;
    log_level = "DEBUG";
    name = if (instances.${nodeName} or null) != null then
      "nomad-${nodeName}"
    else
      null;

    acl.enabled = true;

    ports = {
      http = 4646;
      rpc = 4647;
      serf = 4648;
    };

    tls = {
      http = true;
      rpc = true;
      ca_file = config.age.secrets.nomad-ca.path;
      cert_file = config.age.secrets.nomad-server.path;
      key_file = config.age.secrets.nomad-server-key.path;
      tls_min_version = "tls12";
    };

    vault = {
      enabled = true;
      ca_file = config.age.secrets.nomad-ca.path;
      cert_file = config.age.secrets.nomad-client.path;
      key_file = config.age.secrets.nomad-client-key.path;
      create_from_role = "nomad-cluster";
    };

    consul = {
      address = "127.0.0.1:${toString config.services.consul.ports.http}";
      ssl = false;
      allow_unauthenticated = true;
    };

    telemetry = {
      publish_allocation_metrics = true;
      publish_node_metrics = true;
      datadog_address = "localhost:8125";
      datadog_tags = [ "region:${region}" "role:nomad" ];
    };
  };

  # Used for Consul Connect.
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-arptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
  };
}
