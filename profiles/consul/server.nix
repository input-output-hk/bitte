{ lib, pkgs, config, ... }:
let
  inherit (lib) mapAttrsToList;
  inherit (config.cluster) instances region;
  instance = instances.${config.networking.hostName};
  inherit (instance) privateIP;
in {
  imports = [ ./default.nix ];

  services.consul = {
    bootstrapExpect = 3;
    addresses = { http = "${privateIP} 127.0.0.1"; };
    autoEncrypt.allowTls = true;
    enable = true;
    server = true;
    ui = true;
  };
}
