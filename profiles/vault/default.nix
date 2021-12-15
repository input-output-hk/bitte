{ lib, pkgs, config, ... }:
let
  inherit (config.cluster) region instances kms;
  cfg = config.services.vault;

  full = "/etc/ssl/certs/full.pem";
  ca = "/etc/ssl/certs/ca.pem";
  cert = "/etc/ssl/certs/cert.pem";
  key = "/var/lib/vault/cert-key.pem";
in {
  config = lib.mkIf cfg.enable {
    environment.variables = {
      VAULT_FORMAT = "json";
      VAULT_ADDR = "https://127.0.0.1:8200";
      VAULT_CACERT = "/etc/ssl/certs/full.pem";
    };

    services.vault = {
      logLevel = "trace";

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
        tlsMinVersion = "tls12";
      };

      telemetry = {
        dogstatsdAddr = "localhost:8125";
        dogstatsdTags = [ "region:${region}" "role:vault" ];
      };
    };
  };
}
