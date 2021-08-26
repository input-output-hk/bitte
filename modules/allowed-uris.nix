{ config, lib, ... }:

let cfg = config.nix;

in {
  options.nix.allowedUris = lib.mkOption {
    type = with lib.types; listOf str;
    default = [ ];
  };

  config = lib.mkIf (cfg.allowedUris != [ ]) {
    nix.extraOptions = ''
      allowed-uris = ${toString cfg.allowedUris}
    '';
  };
}
