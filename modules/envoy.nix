{ lib, config, ... }:
let cfg = config.services.envoy;
in {
  options = { services.envoy.enable = lib.mkEnableOption "Enable Envoy"; };

  config = { systemd.services.envoy = lib.mkIf cfg.enable { }; };
}
