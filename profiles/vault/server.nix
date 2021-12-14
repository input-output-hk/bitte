{ config, nodeName, lib, ... }:
let 
  inherit (config.cluster) instances;
  instance = instances.${nodeName};
in {
  imports = [ ./default.nix ./policies.nix ];
  config = {
    services.vault = {
      enable = true;
      ui = true;

      apiAddr = "https://${instance.privateIP}:8200";
      clusterAddr = "https://${instance.privateIP}:8201";

      listener.tcp = { clusterAddress = "${instance.privateIP}:8201"; };
    };
  };
}
