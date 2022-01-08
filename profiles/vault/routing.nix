{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ]; };

  Switches = {
    services.vault-agent-core.enable = true;
    services.vault.enable = lib.mkForce false;
  };

  Config = {
    services.vault-agent-core = {
      vaultAddress = "https://core.vault.service.consul:8200";
    };
    services.vault-agent = {

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
