{ config, lib, ... }: {
  options = {
    services.vault-agent-monitoring = {
      enable = lib.mkEnableOption "Start vault-agent for cores";
    };
  };

  config = lib.mkIf config.services.vault-agent-monitoring.enable {
    environment.variables.VAULT_ADDR = "http://127.0.0.1:8200";

    services = {
      vault.enable = lib.mkForce false;

      vault-agent-core = {
        enable = true;
        vaultAddress = "https://core.vault.service.consul:8200";
      };

      vault-agent = {
        listener = [{
          type = "tcp";
          address = "127.0.0.1:8200";
          tlsDisable = true;
        }];
      };
    };
  };
}
