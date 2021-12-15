{ config, nodeName, lib, pkiFiles, ... }:
let
  inherit (config.cluster) instances;
  instance = instances.${nodeName};
in {
  imports = [ ./default.nix ./policies.nix ];
  config = {
    services.vault = {
      enable = true;
      ui = true;

      apiAddr = "https://${instance.privateIP}:8200";
      clusterAddr = "https://${instance.privateIP}:8201";

      listener.tcp = { clusterAddress = "${instance.privateIP}:8201"; };

      storage.raft = let
        vcfg = config.services.vault.listener.tcp;
        instances = lib.filterAttrs (k: v: lib.hasPrefix "core-" k)
          config.cluster.instances;
      in lib.mkDefault {
        retryJoin = lib.mapAttrsToList (_: v: {
          leaderApiAddr = "https://${v.privateIP}:8200";
          leaderCaCertFile = vcfg.tlsClientCaFile;
          leaderClientCertFile = vcfg.tlsCertFile;
          leaderClientKeyFile = vcfg.tlsKeyFile;
        }) instances;
      };
    };

    services.vault-snapshots.enable = true;
  };
}
