{ lib, pkgs, config, nodeName, ... }:
let
  inherit (lib) mapAttrsToList;
  inherit (config.cluster) instances region;
  instance = instances.${nodeName};
in {
  imports = [ ./default.nix ./policies.nix ];

  services.consul = {
    bootstrapExpect = 3;
    addresses.http = lib.mkDefault "${instance.privateIP} 127.0.0.1";
    # autoEncrypt = {
    #   allowTls = true;
    #   tls = true;
    # };
    enable = true;
    server = true;
    ui = true;
  };
}
