{ lib, pkgs, config, ... }:
let inherit (config.cluster) region instances;
in {
  imports = [ ./default.nix ./policies.nix ];

  services.nomad = {
    enable = true;

    datacenter = config.cluster.region;

    server = {
      enabled = true;

      bootstrap_expect = 3;

      server_join = {
        retry_join = (lib.mapAttrsToList (_: v: v.privateIP) instances)
          ++ [ "provider=aws region=${region} tag_key=Nomad tag_value=server" ];
      };

      default_scheduler_config = {
        preemption_config = {
          batch_scheduler_enabled = true;
          system_scheduler_enabled = true;
          service_scheduler_enabled = true;
        };
      };
    };
  };
}
