{ lib, pkgs, config, nodeName, ... }:
let
  inherit (config.cluster) region;
in {
  imports = [ ./default.nix ./policies.nix ];

  services.consul = {
    bootstrapExpect = 3;
    addresses = { http = "${config.currentCoreNode.privateIP} 127.0.0.1"; };
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
