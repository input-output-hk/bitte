{ config, nodeName, lib, pkiFiles, ... }: let

  Imports = { imports = [
    ./common.nix
    ./policies.nix

    ./secrets-provisioning/hashistack.nix
  ]; };

  Switches = {
    services.vault.enable = true;
    services.vault-snapshots.enable = true;
    services.vault.ui = true;
  };

  Config = let ownedKey = "/var/lib/vault/cert-key.pem";
  in {
    services.vault-agent = {
      role = "core";
      vaultAddress = "https://127.0.0.1:8200"; # avoid depending on any network (at least for the agent)
      listener = lib.mkForce []; # we already have the vault server binding here
    };
    services.vault = {
      logLevel = "trace";

      apiAddr = "https://${config.currentCoreNode.privateIP}:8200";
      clusterAddr = "https://${config.currentCoreNode.privateIP}:8201";

      listener.tcp = {
        clusterAddress = "${config.currentCoreNode.privateIP}:8201";
        address = "0.0.0.0:8200";
        tlsClientCaFile = pkiFiles.caCertFile;
        tlsCertFile = pkiFiles.certChainFile;
        tlsKeyFile = ownedKey;
        tlsMinVersion = "tls12";
      };

      seal.awskms = {
        kmsKeyId = config.cluster.kms;
        inherit (config.cluster) region;
      };

      disableMlock = true;

      telemetry = {
        dogstatsdAddr = "localhost:8125";
        dogstatsdTags = [ "region:${config.cluster.region}" "role:vault" ];
      };

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

    environment.variables = {
      VAULT_FORMAT = "json";
      VAULT_ADDR = "https://127.0.0.1:8200";
      VAULT_CACERT = pkiFiles.caCertFile;
    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]

