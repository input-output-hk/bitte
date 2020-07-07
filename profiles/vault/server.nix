{ config, nodeName, ... }:
let
  inherit (config.cluster) instances;
  instance = instances.${nodeName};
  inherit (instance) privateIP;

in {
  imports = [ ./default.nix ];
  config = {
    services.vault = {
      enable = true;
      ui = true;

      apiAddr = "https://${privateIP}:8200";
      clusterAddr = "https://${privateIP}:8201";

      listener.tcp = {
        address = "0.0.0.0:8200";
        clusterAddress = "${privateIP}:8201";
        tlsClientCaFile = "/etc/ssl/certs/all.pem";
        tlsCertFile = "/var/lib/vault/certs/cert.pem";
        tlsKeyFile = "/var/lib/vault/certs/cert-key.pem";
        tlsMinVersion = "tls13";
      };
    };
  };
}
