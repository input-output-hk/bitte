{
  lib,
  pkgs,
  config,
  nodeName,
  ...
}: let
  Imports = {imports = [./common.nix ./policies.nix];};

  Switches = {
    services.hashi-snapshots.enableConsul = true;
    services.consul.server = true;

    # Consul UI is intentionally served exclusively through routing machine
    services.consul.uiConfig.enabled = false;
  };

  Config = {
    # Consul firewall references:
    #   https://support.hashicorp.com/hc/en-us/articles/1500011608961-Checking-Consul-Network-Connectivity
    #   https://www.consul.io/docs/install/ports
    #
    # Consul ports specific to servers
    networking.firewall.allowedTCPPorts = [
      8600 # dns
    ];
    networking.firewall.allowedUDPPorts = [
      8600 # dns
    ];

    services.consul = {
      bootstrapExpect = 3;
      addresses = {http = "${config.currentCoreNode.privateIP} 127.0.0.1";};
    };
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
