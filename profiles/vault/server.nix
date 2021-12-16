{ config, nodeName, lib, pkiFiles, ... }: {
  imports = [ ./default.nix ./policies.nix ];
  config = {
    services.vault = {
      enable = true;
      ui = true;

      apiAddr = "https://${config.currentCoreNode.privateIP}:8200";
      clusterAddr = "https://${config.currentCoreNode.privateIP}:8201";

      listener.tcp = { clusterAddress = "${config.currentCoreNode.privateIP}:8201"; };

      storage.raft = let
        vcfg = config.services.vault.listener.tcp;
        coreNodesWithCorePrefix = lib.filterAttrs (k: v: lib.hasPrefix "core-" k)
          config.cluster.coreNodes;
      in lib.mkDefault {
        retryJoin = lib.mapAttrsToList (_: coreNode: {
          leaderApiAddr = "https://${coreNode.privateIP}:8200";
          leaderCaCertFile = vcfg.tlsClientCaFile;
          leaderClientCertFile = vcfg.tlsCertFile;
          leaderClientKeyFile = vcfg.tlsKeyFile;
        }) coreNodesWithCorePrefix;
      };
    };

    services.vault-snapshots.enable = true;
  };
}
