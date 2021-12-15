{ config, nodeName, lib, ... }:
let
  inherit (config.cluster) instances;
  instance = instances.${nodeName};

  full = "/etc/ssl/certs/full.pem";
  cert = "/etc/ssl/certs/cert.pem";
  key = "/var/lib/vault/cert-key.pem";
in {
  imports = [ ./default.nix ./policies.nix ];
  config = {
    services.vault = {
      enable = true;
      ui = true;

      apiAddr = "https://${instance.privateIP}:8200";
      clusterAddr = "https://${instance.privateIP}:8201";

      listener.tcp = { clusterAddress = "${instance.privateIP}:8201"; };

      storage.consul = lib.mkDefault {
        address = "127.0.0.1:8500";
        tlsCaFile = full;
        tlsCertFile = cert;
        tlsKeyFile = key;
      };
    };
  };
}
