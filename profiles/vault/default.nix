{ lib, pkgs, config, pkiFiles, ... }:
let
  cfg = config.services.vault;
  ownedKey = "/var/lib/vault/cert-key.pem";
in {
  config = lib.mkIf cfg.enable {
    environment.variables = {
      VAULT_FORMAT = "json";
      VAULT_ADDR = lib.mkDefault "https://127.0.0.1:8200";
      VAULT_CACERT = pkiFiles.caCertFile;
    };

    services.vault = {
      logLevel = "trace";

      seal.awskms = {
        kmsKeyId = config.cluster.kms;
        inherit (config.cluster) region;
      };

      disableMlock = true;

      listener.tcp = {
        address = "0.0.0.0:8200";
        tlsClientCaFile = pkiFiles.caCertFile;
        tlsCertFile = pkiFiles.certChainFile;
        tlsKeyFile = ownedKey;
        tlsMinVersion = "tls12";
      };

      telemetry = {
        dogstatsdAddr = "localhost:8125";
        dogstatsdTags = [ "region:${config.cluster.region}" "role:vault" ];
      };
    };
  };
}
