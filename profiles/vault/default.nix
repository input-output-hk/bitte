{ lib, pkgs, config, pkiFiles, ... }:
let
  inherit (lib) mapAttrsToList mkIf;
  inherit (config.cluster) region instances kms;
  cfg = config.services.vault;
  ownedKey = "/var/lib/vault/cert-key.pem";
in {
  config = mkIf cfg.enable {
    environment.variables = {
      VAULT_FORMAT = "json";
      VAULT_ADDR = lib.mkDefault "https://127.0.0.1:8200";
      VAULT_CACERT = pkiFiles.caCertFile;
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
        tlsClientCaFile = pkiFiles.caCertFile;
        tlsCertFile = pkiFiles.certChainFile;
        tlsKeyFile = ownedKey;
        tlsMinVersion = "tls12";
      };

      telemetry = {
        dogstatsdAddr = "localhost:8125";
        dogstatsdTags = [ "region:${region}" "role:vault" ];
      };
    };
  };
}
