{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ./common.nix ]; };

  Switches = {};

  Config = let
    cfg = config.services.consul;
    isDocker = config.virtualisation.docker.enable == true;
  in {
    # Consul firewall references:
    #   https://support.hashicorp.com/hc/en-us/articles/1500011608961-Checking-Consul-Network-Connectivity
    #   https://www.consul.io/docs/install/ports
    #
    # Consul ports specific to clients also running nomad
    networking.firewall.allowedTCPPortRanges = lib.mkIf config.services.nomad.enable [
      {
        from = cfg.ports.sidecarMinPort;
        to = cfg.ports.sidecarMaxPort;
      }
      {
        from = cfg.ports.exposeMinPort;
        to = cfg.ports.exposeMaxPort;
      }
    ];

    services.consul = {
      addresses.http = lib.mkIf isDocker "127.0.0.1 {{ GetInterfaceIP \"docker0\" }}";
      ports = {
        # Default dynamic port ranges for consul clients.
        # Nomad default ephemeral dynamic port range will need to be adjusted to avoid random collision.
        #
        # Refs:
        #   https://www.nomadproject.io/docs/job-specification/network#dynamic-ports
        #   https://www.consul.io/docs/agent/options#ports
        #   https://github.com/hashicorp/consul/issues/12253
        #   https://github.com/hashicorp/nomad/issues/4285
        sidecarMinPort = 21000;
        sidecarMaxPort = 21255;
        exposeMinPort = 21500;
        exposeMaxPort = 21755;
      };
    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
