{ lib, pkgs, config, ... }:
let
  inherit (lib) mapAttrsToList mkIf;
  inherit (config.cluster) region instances kms;
in {
  config = mkIf config.services.vault.enable {
    environment.variables = {
      VAULT_FORMAT = "json";
      VAULT_ADDR = "https://127.0.0.1:8200/";
      VAULT_CACERT = "/etc/ssl/certs/ca.pem";
    };

    services.vault = {
      serviceRegistration.consul = {
        scheme = "https";
        address = "127.0.0.1:8501";
        tlsClientCaFile = "/etc/ssl/certs/ca.pem";
        tlsCertFile = "/var/lib/vault/certs/cert.pem";
        tlsKeyFile = "/var/lib/vault/certs/cert-key.pem";
      };

      seal.awskms = {
        kmsKeyId = kms;
        inherit region;
      };

      disableMlock = true;

      listener.tcp = {
        address = "0.0.0.0:8200";
        tlsClientCaFile = "/etc/ssl/certs/all.pem";
        tlsCertFile = "/var/lib/vault/certs/cert.pem";
        tlsKeyFile = "/var/lib/vault/certs/cert-key.pem";
        tlsMinVersion = "tls13";
      };

      storage.raft = {
        retryJoin = mapAttrsToList (_: v: {
          leaderApiAddr = "https://${v.privateIP}:8200";
          leaderCaCertFile = "/var/lib/vault/certs/${v.name}.pem";
          # leaderCaCertFile = "/etc/ssl/certs/all.pem";
          leaderClientCertFile = config.services.vault.listener.tcp.tlsCertFile;
          leaderClientKeyFile = config.services.vault.listener.tcp.tlsKeyFile;
        }) instances;
      };
    };
  };
}
