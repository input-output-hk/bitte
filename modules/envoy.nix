{ lib, config, ... }:
let
  cfg = config.services.envoy;
  inherit (lib) mkIf mkEnableOption;
in
{
  options = { services.envoy.enable = mkEnableOption "Enable Envoy"; };

  config = { systemd.services.envoy = mkIf cfg.enable { }; };
}
