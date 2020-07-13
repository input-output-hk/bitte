{ config, nodeName, ... }:
let
  inherit (config.cluster) instances;
  instance = instances.${nodeName};
  inherit (instance) privateIP;

in {
  imports = [ ./default.nix ];
  config = {
    services.vault = {
      enable = true;
      ui = true;

      apiAddr = "https://${privateIP}:8200";
      clusterAddr = "https://${privateIP}:8201";

      listener.tcp = { clusterAddress = "${privateIP}:8201"; };
    };
  };
}
