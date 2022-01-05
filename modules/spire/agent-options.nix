{ lib, pkgs, ... }: {
  options.services.spire-agent = {
    enable = lib.mkEnableOption "Enable the spire agent.";

    package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.spire-agent;
    };
  };
}
