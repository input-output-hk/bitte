{ lib, pkgs, config, ... }:
let
  inherit (config.cluster) name region domain kms instances;
  inherit (lib) mkIf mapAttrsToList;
in {
  environment.variables = { NOMAD_ADDR = "https://127.0.0.1:4646"; };

  services.nomad = {
    dataDir = /var/lib/nomad;
    logLevel = "DEBUG";
    datacenter = config.cluster.region;
    name = config.networking.hostName;

    acl.enabled = true;

    ports = {
      http = 4646;
      rpc = 4647;
      serf = 4648;
    };

    tls = {
      http = true;
      rpc = true;
      caFile = "/etc/ssl/certs/ca.pem";
      certFile = "/var/lib/nomad/certs/cert.pem";
      keyFile = "/var/lib/nomad/certs/cert-key.pem";
      tlsMinVersion = "tls12";
    };

    consul = {
      address = "127.0.0.1:8501";
      ssl = true;
      caFile = "/etc/ssl/certs/ca.pem";
      certFile = "/var/lib/nomad/certs/cert.pem";
      keyFile = "/var/lib/nomad/certs/cert-key.pem";
      allowUnauthenticated = false;
    };
  };

  # Used for Consul Connect and requires reboot?
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-arptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
  };
}
