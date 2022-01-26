{ config, lib, pkgs, ... }: let

  Imports = { imports = [
    ./secrets-provisioning/cert-identity.nix
  ]; };

  Switches = {
    services.vault-agent.enable = true;
  };

  Config = let
    cfg = config.services.vault-agent;
    deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  in {
    environment.variables.VAULT_ADDR = lib.mkDefault "http://127.0.0.1:8200";
    services.vault-agent = {
      vaultAddress = lib.mkDefault "https://core.vault.service.consul:8200";
      listener = [{
        type = "tcp";
        address = "127.0.0.1:8200";
        tlsDisable = true;
      }];

      autoAuthMethod = if deployType == "aws" then "aws" else "cert";

      autoAuthConfig = if cfg.autoAuthMethod == "aws" then {
        type = "iam";
        role = "${config.cluster.name}-${config.services.vault-agent.role}";
        header_value = config.cluster.domain;
      } else if cfg.autoAuthMethod == "cert" then {
        name = "vault-agent-${cfg.role}";
        ca_cert = config.age.secrets.vault-ca.path;
        client_cert = config.age.secrets.vault-client.path;
        client_key = config.age.secrets.vault-client-key.path;
      } else (abort "Unknown vault autoAuthMethod");
    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
