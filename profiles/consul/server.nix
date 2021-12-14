{ lib, pkgs, config, nodeName, ... }:
let
  inherit (config.cluster) instances region;
  instance = instances.${nodeName};
  inherit (instance) privateIP;
in {
  imports = [ ./default.nix ./policies.nix ];

  services.consul = {
    bootstrapExpect = 3;
    addresses = { http = "${privateIP} 127.0.0.1"; };
    # autoEncrypt = {
    #   allowTls = true;
    #   tls = true;
    # };
    enable = true;
    server = true;
    ui = true;
  };

  services.consul-snapshots.enable = true;
}
