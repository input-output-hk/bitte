{ lib, pkgs, config, nodeName, ... }: let

  Imports = { imports = [ ./common.nix ./policies.nix ]; };

  Switches = {
    services.consul-snapshots.enable = true;
    services.consul.server = true;
    services.consul.ui = true;
  };

  Config = {
    services.consul = {
      bootstrapExpect = 3;
      addresses = { http = "${config.currentCoreNode.privateIP} 127.0.0.1"; };
      # autoEncrypt = {
      #   allowTls = true;
      #   tls = true;
      # };
    };
  };

in lib.mkMerge [
  Imports
  Switches
  Config
]

