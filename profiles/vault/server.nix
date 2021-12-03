{ config, nodeName, lib, pkiFiles, ... }:
let
  inherit (config.cluster) instances;
  inherit (instances.${nodeName}) privateIP;

  owendKey = "/var/lib/vault/cert-key.pem";
in
{
  imports = [ ./default.nix ./policies.nix ];
  config = {
    services.vault = {
      enable = true;
      ui = true;

      apiAddr = "https://${privateIP}:8200";
      clusterAddr = "https://${privateIP}:8201";

      listener.tcp = { clusterAddress = "${privateIP}:8201"; };

      storage.consul = lib.mkDefault {
        address = "127.0.0.1:8500";
        tlsCaFile = pkiFiles.caCertFile;
        tlsCertFile = pkiFiles.certChainFile;
        tlsKeyFile = owendKey;
      };
    };

    services.vault-snapshots.enable = true;
  };
}
