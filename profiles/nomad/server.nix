{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ./common.nix ./policies.nix ]; };

  Switches = {
    services.nomad.server.enabled = true;
    services.nomad-snapshots.enable = true;
  };

  Config = {
    services.nomad = {
      datacenter = config.cluster.region;

      server = {
        bootstrap_expect = 3;

        server_join = {
          retry_join = (lib.mapAttrsToList (_: v: v.privateIP) config.cluster.coreNodes)
            ++ [ "provider=aws region=${config.cluster.region} tag_key=Nomad tag_value=server" ];
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

in Imports // lib.mkMerge [
  Switches
  Config
]
