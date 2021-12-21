{ config, nodeName, lib, pkiFiles, ... }: let

  Imports = { imports = [ ./common.nix ./policies.nix ]; };

  Switches = {
    services.vault-snapshots.enable = true;
    services.vault.ui = true;
  };

  Config = {
    services.vault = {
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
  };

in lib.mkMerge [
  Imports
  Switches
  Config
]

