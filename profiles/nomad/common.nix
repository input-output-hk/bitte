{ config, lib, pkgs, nodeName, pkiFiles, ... }: let

  Imports = { imports = []; };

  Switches = {
    services.nomad.enable = true;
    services.nomad.acl.enabled = true;
    services.nomad.vault.enabled = true;
  };

  Config = let
    inherit (config.cluster) region;
    deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
    datacenter = config.currentCoreNode.datacenter or config.currentAwsAutoScalingGroup.datacenter;

    ownedChain = "/var/lib/nomad/full.pem";
    ownedKey = "/var/lib/nomad/cert-key.pem";
    consulOwnedChain = "/var/lib/consul/full.pem";
    consulOwnedKey = "/var/lib/consul/cert-key.pem";
  in {

    environment.variables = {
      NOMAD_ADDR =
        "https://127.0.0.1:${toString config.services.nomad.ports.http}";
    };

    services.nomad = {
      data_dir = /var/lib/nomad;
      log_level = "DEBUG";
      name = if (config.currentCoreNode or null) != null then
        "nomad-${nodeName}"
      else
        null;

      ports = {
        http = 4646;
        rpc = 4647;
        serf = 4648;
      };

      tls = {
        http = true;
        rpc = true;
        ca_file = pkiFiles.caCertFile;
        cert_file = ownedChain;
        key_file = ownedKey;
        tls_min_version = "tls12";
      };

      vault = {
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
        cert_file = consulOwnedChain;
        key_file = consulOwnedKey;
      };

      telemetry = {
        publish_allocation_metrics = true;
        publish_node_metrics = true;
        datadog_address = "localhost:8125";
        datadog_tags = [
          (if deployType == "aws" then "region:${region}" else "datacenter:${datacenter}")
          "role:nomad"
        ];
      };
    };

    # Used for Consul Connect.
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-arptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
