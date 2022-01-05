{ lib, pgks, ... }: {
  options.services.spire-server = {
    enable = lib.mkEnableOption "Enable the spire server.";

    package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.spire-server;
    };

    configFile = lib.mkOption {
      type = with lib.types; path;
      description = "Path to CoreRAD TOML configuration file.";
    };

  };
}
