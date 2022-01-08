{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ]; };

  Switches = {
    services.vault-agent.enable = true;
  };

  Config = {
    environment.variables.VAULT_ADDR = lib.mkDefault "http://127.0.0.1:8200";
    services.vault-agent = {
      vaultAddress = lib.mkDefault "https://core.vault.service.consul:8200";
      listener = [{
        type = "tcp";
        address = "127.0.0.1:8200";
        tlsDisable = true;
      }];
      autoAuthMethod = "aws";

      autoAuthConfig = {
        type = "iam";
        role = "${config.cluster.name}-${config.services.vault-agent.role}";
        header_value = config.cluster.domain;
      };

    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
