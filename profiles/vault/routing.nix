{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ./common.nix ./core-secrets-templating.nix ]; };

  Switches = { };

  Config = {
    services.vault-agent = {
      role = "core";
      vaultAddress = "https://core.vault.service.consul:8200";
      listener = [{
        type = "tcp";
        address = "127.0.0.1:8200";
        tlsDisable = true;
      }];
    };

    environment.variables.VAULT_ADDR = "http://127.0.0.1:8200";
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
