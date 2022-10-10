{
  config,
  lib,
  pkgs,
  ...
}: let
  Imports = {imports = [./common.nix ./policies.nix];};

  Switches = {
    services.nomad.server.enabled = true;
    services.hashi-snapshots.enableNomad = true;
  };

  Config = let
    inherit (config.cluster) nodes region;
    deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
    datacenter = config.currentCoreNode.datacenter or config.cluster.region;

    cfg = config.services.nomad;
  in {
    # Nomad firewall references:
    #   https://www.nomadproject.io/docs/install/production/requirements
    #
    # Nomad ports specific to servers
    networking.firewall.allowedTCPPorts = [
      4648 # serf wan
    ];
    networking.firewall.allowedUDPPorts = [
      4648 # serf wan
    ];

    services.nomad = {
      datacenter =
        if builtins.elem deployType ["aws" "awsExt"]
        then region
        else datacenter;

      server = {
        bootstrap_expect = 3;

        server_join = {
          retry_join =
            (lib.mapAttrsToList (_: v: v.privateIP) (lib.filterAttrs (k: v: lib.elem k cfg.serverNodeNames) nodes))
            ++ (lib.optionals (builtins.elem deployType ["aws" "awsExt"])
              ["provider=aws region=${region} tag_key=Nomad tag_value=server"]);
        };

        default_scheduler_config = {
          memory_oversubscription_enabled = true;

          preemption_config = {
            batch_scheduler_enabled = true;
            system_scheduler_enabled = true;
            service_scheduler_enabled = true;
          };
        };
      };
    };

    systemd.services.nomad.environment = {
      CONSUL_HTTP_ADDR = "http://127.0.0.1:8500";
    };
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
