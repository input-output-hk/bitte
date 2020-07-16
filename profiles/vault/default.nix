{ lib, pkgs, config, ... }:
let
  inherit (lib) mapAttrsToList mkIf;
  inherit (config.cluster) region instances kms;
  cfg = config.services.vault;

  full = "/etc/ssl/certs/full.pem";
  ca = "/etc/ssl/certs/ca.pem";
  cert = "/etc/ssl/certs/cert.pem";
  key = "/var/lib/vault/cert-key.pem";
in {
  config = mkIf cfg.enable {
    environment.variables = {
      VAULT_FORMAT = "json";
      VAULT_ADDR = "https://vault.service.consul:8200/";
      VAULT_CACERT = "/etc/ssl/certs/full.pem";
    };

    services.vault = {
      logLevel = "trace";

      serviceRegistration.consul = {
        scheme = "https";
        address = "consul.service.consul:8501";
        tlsClientCaFile = full;
        tlsCertFile = cert;
        tlsKeyFile = key;
      };

      seal.awskms = {
        kmsKeyId = kms;
        inherit region;
      };

      disableMlock = true;

      listener.tcp = {
        address = "0.0.0.0:8200";
        tlsClientCaFile = full;
        tlsCertFile = cert;
        tlsKeyFile = key;
        tlsMinVersion = "tls13";
      };

      storage.consul = {
        address = "consul.service.consul:8500";
        tlsCaFile = full;
        tlsCertFile = cert;
        tlsKeyFile = key;
      };

      # storage.raft = {
      #   retryJoin = mapAttrsToList (_: v: {
      #     leaderApiAddr = "https://${v.privateIP}:8200";
      #     leaderCaCertFile = "/var/lib/vault/certs/${v.name}.pem";
      #     # leaderCaCertFile = "/etc/ssl/certs/ca.pem";
      #     leaderClientCertFile = config.services.vault.listener.tcp.tlsCertFile;
      #     leaderClientKeyFile = config.services.vault.listener.tcp.tlsKeyFile;
      #   }) instances;
      # };
    };
  };
}
