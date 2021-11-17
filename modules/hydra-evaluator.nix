{ config, lib, pkgs, ... }:

with lib;
with types;

let cfg = config.services.hydra.evaluator;
in
{
  options.services.hydra.evaluator = {
    restricted = (mkEnableOption "restricted evaluation mode") // {
      default = true;
    };
    pure = mkEnableOption "pure evaluation mode";
  };

  config = mkIf config.services.hydra.enable {
    services.hydra.extraConfig = ''
      evaluator_restrict_eval = ${boolToString cfg.restricted}
      evaluator_pure_eval = ${boolToString cfg.pure}
    '';
  };
}
