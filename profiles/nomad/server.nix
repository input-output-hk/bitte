{ lib, pkgs, config, ... }:
let inherit (config.cluster) region instances;
in {
  imports = [ ./default.nix ./policies.nix ];

  age.secrets = {
    nomad-full = {
      file = ../../encrypted/ssl/server-full.age;
      path = "/var/lib/nomad/full.pem";
    };

    nomad-ca = {
      file = ../../encrypted/ssl/ca.age;
      path = "/var/lib/nomad/ca.pem";
    };

    nomad-server = {
      file = ../../encrypted/ssl/server.age;
      path = "/var/lib/nomad/server.pem";
    };

    nomad-server-key = {
      file = ../../encrypted/ssl/server-key.age;
      path = "/var/lib/nomad/server-key.pem";
    };

    nomad-client = {
      file = ../../encrypted/ssl/client.age;
      path = "/var/lib/nomad/client.pem";
    };

    nomad-client-key = {
      file = ../../encrypted/ssl/client-key.age;
      path = "/var/lib/nomad/client-key.pem";
    };
  };

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
