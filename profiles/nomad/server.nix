{ lib, pkgs, config, ... }: {
  imports = [ ./default.nix ./policies.nix ];

  services.nomad = {
    enable = true;

    datacenter = lib.mkDefault "dc1";

    server = {
      enabled = true;

      bootstrap_expect = 3;

      server_join = {
        retry_join =
          lib.mapAttrsToList (_: v: v.privateIP) config.cluster.instances;
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
