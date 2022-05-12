{ lib, config, ... }:
let cfg = config.services.envoy;
in {
  disabledModules = [ "services/networking/envoy.nix" ];
  options = { services.envoy.enable = lib.mkEnableOption "Enable Envoy"; };

  config = { systemd.services.envoy = lib.mkIf cfg.enable { }; };
}
