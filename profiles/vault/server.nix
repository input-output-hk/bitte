{
  config,
  nodeName,
  lib,
  pkiFiles,
  ...
}: let
  Imports = {
    imports = [
      ./common.nix
      ./policies.nix
    ];
  };

  Switches = let
    cfg = config.services.hashi-snapshots;
  in {
    services.vault.enable = true;
    services.hashi-snapshots.enableVault = true;

    # Do not include vault replicas in snapshotting until replica snapshot bug is resolved
    # Ref: https://github.com/hashicorp/vault/issues/15258
    services.hashi-snapshots.vault.hourly = cfg.defaultHourlyOpts // cfg.defaultHashiOpts.vault // {includeReplica = false;};
    services.hashi-snapshots.vault.daily = cfg.defaultDailyOpts // cfg.defaultHashiOpts.vault // {includeReplica = false;};

    services.vault.ui = true;
  };

  Config = let
    inherit (config.cluster) nodes region;
    deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
    datacenter = config.currentCoreNode.datacenter or config.cluster.region;
    ownedChain = "/var/lib/vault/full.pem";
    ownedKey = "/var/lib/vault/cert-key.pem";

    serverAddress =
      if config.services.vault.serverNameAddressing
      then "${nodeName}.internal"
      else config.currentCoreNode.privateIP;
  in {
    # Vault firewall references:
    #   https://www.vaultproject.io/docs/configuration/listener/tcp
    #   https://learn.hashicorp.com/tutorials/vault/reference-architecture
    #
    # Vault ports specific to servers
    networking.firewall = {
      allowedTCPPorts = [
        8200 # http api
        8201 # rpc
      ];
    };

    services.vault-agent = {
      role = "core";
      vaultAddress = "https://127.0.0.1:8200"; # avoid depending on any network (at least for the agent)
      listener = lib.mkForce []; # we already have the vault server binding here
    };
    services.vault = {
      logLevel = "trace";

      apiAddr = "https://${serverAddress}:8200";
      clusterAddr = "https://${serverAddress}:8201";

      listener.tcp = {
        clusterAddress = "${config.currentCoreNode.privateIP}:8201";
        address = "0.0.0.0:8200";
        tlsClientCaFile = pkiFiles.caCertFile;
        tlsCertFile = ownedChain;
        tlsKeyFile = ownedKey;
        tlsMinVersion = "tls12";
      };

      seal = lib.mkIf (builtins.elem deployType ["aws" "awsExt"]) {
        awskms = {
          kmsKeyId = config.cluster.kms;
          inherit region;
        };
      };

      disableMlock = true;

      telemetry = {
        dogstatsdAddr = "localhost:8125";
        dogstatsdTags = [
          "role:vault"
          (
            if (builtins.elem deployType ["aws" "awsExt"])
            then "region:${region}"
            else "datacenter:${datacenter}"
          )
        ];
      };

      storage.raft = let
        vcfg = config.services.vault;
        vaultServers =
          lib.filterAttrs (k: v: lib.elem k vcfg.serverNodeNames) nodes;
        vaultAddress = k: v:
          if config.services.vault.serverNameAddressing
          then "${k}.internal"
          else v.privateIP;
      in
        lib.mkDefault {
          retryJoin =
            lib.mapAttrsToList (_: vaultServer: {
              leaderApiAddr = "https://${vaultAddress _ vaultServer}:8200";
              leaderCaCertFile = vcfg.listener.tcp.tlsClientCaFile;
              leaderClientCertFile = vcfg.listener.tcp.tlsCertFile;
              leaderClientKeyFile = vcfg.listener.tcp.tlsKeyFile;
            })
            vaultServers;
        };
    };

    environment.variables = {
      VAULT_FORMAT = "json";
      VAULT_ADDR = "https://127.0.0.1:8200";
      VAULT_CACERT = pkiFiles.caCertFile;
    };
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
