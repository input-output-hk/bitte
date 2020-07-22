{ lib, pkgs, config, nodeName, ... }:
let
  inherit (config.cluster) name region domain kms instances;
  inherit (lib) mkIf mapAttrsToList;

  full = "/etc/ssl/certs/full.pem";
  ca = "/etc/ssl/certs/ca.pem";
  cert = "/etc/ssl/certs/cert.pem";
  key = "/var/lib/nomad/cert-key.pem";
in {
  environment.variables = {
    NOMAD_ADDR =
      "https://127.0.0.1:${toString config.services.nomad.ports.http}";
  };

  services.nomad = {
    dataDir = /var/lib/nomad;
    logLevel = "DEBUG";
    datacenter = config.cluster.region;
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
      caFile = full;
      certFile = cert;
      keyFile = key;
      tlsMinVersion = "tls12";
    };

    consul = {
      address = "127.0.0.1:${toString config.services.consul.ports.https}";
      ssl = true;
      caFile = full;
      certFile = cert;
      keyFile = key;
      allowUnauthenticated = false;
    };

    telemetry = {
      datadogAddress = "localhost:8125";
      datadogTags = [ "region:${region}" "role:nomad" ];
    };
  };

  # Used for Consul Connect and requires reboot?
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-arptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
  };
}
