{ lib, pkgs, config, nodeName, pkiFiles, ... }:
let
  inherit (config.cluster) name region domain kms instances;
  inherit (lib) mkIf mapAttrsToList;

  ownedKey = "/var/lib/nomad/cert-key.pem";
in {
  environment.variables = {
    NOMAD_ADDR =
      "https://127.0.0.1:${toString config.services.nomad.ports.http}";
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
      ca_file = pkiFiles.caCertFile;
      cert_file = pkiFiles.certChainFile;
      key_file = ownedKey;
      tls_min_version = "tls12";
    };

    vault = {
      enabled = true;
      # ca_file = pkiFiles.caCertFile;
      # cert_file = pkiFiles.certChainFile;
      # key_file = ownedKey;
      create_from_role = "nomad-cluster";
    };

    consul = {
      address = "127.0.0.1:${toString config.services.consul.ports.https}";
      ssl = true;
      allow_unauthenticated = true;
      ca_file = pkiFiles.caCertFile;
      cert_file = pkiFiles.certChainFile;
      key_file = ownedKey;
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
