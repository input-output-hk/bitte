{
  lib,
  pkgs,
  config,
  bittelib,
  pkiFiles,
  ...
}: {
  options = {
    services.bootstrap = {
      extraConsulInitialTokensConfig = lib.mkOption {
        type = with lib.types; lines;
        default = "";
        description = "Extra Consul initial tokens configuration.";
      };
      extraNomadBootstrapConfig = lib.mkOption {
        type = with lib.types; lines;
        default = "";
        description = "Extra Nomad bootstrap configuration.";
      };
      extraVaultBootstrapConfig = lib.mkOption {
        type = with lib.types; lines;
        default = "";
        description = "Extra Vault bootstrap configuration.";
      };
      extraVaultSetupConfig = lib.mkOption {
        type = with lib.types; lines;
        default = "";
        description = "Extra Vault setup configuration.";
      };
    };
  };
}
