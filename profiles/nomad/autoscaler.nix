{ pkgs, config, lib, ... }:
let
  asgs = config.cluster.autoscalingGroups;

  mkQuery = type:
    { region, ... }:
    lib.replaceStrings [ "\n" " " ] [ "" "" ] ''
      sum(
        nomad_client_allocated_${type}_value{datacenter="${region}"}
        * 100
        / ( nomad_client_unallocated_${type}_value{datacenter="${region}"}
          + nomad_client_allocated_${type}_value{datacenter="${region}"} )
      ) / count(nomad_client_allocated_${type}_value{datacenter="${region}"})
    '';

  memoryQuery = mkQuery "memory";
  cpuQuery = mkQuery "cpu";

  policies = lib.flip lib.mapAttrs' asgs (name: asg: {
    name = "nomad-autoscaler.d/policies/${name}.json";
    value.source = pkgs.toPrettyJSON "${name}.json" {
      scaling.cluster_policy = {
        enabled = true;
        min = 1;
        max = 3;

        policy = {
          cooldown = "2m";
          evaluation_interval = "1m";

          check.cpu_allocated_percentage = {
            source = "victoriametrics";
            query = cpuQuery asg;
            strategy.target-value.target = 70;
          };

          check.mem_allocated_percentage = {
            source = "victoriametrics";
            query = memoryQuery asg;
            strategy.target-value.target = 70;
          };

          target."${name}" = {
            dry-run = "true";

            aws_asg_name = asg.uid;
            node_class = "client";
            node_drain_deadline = "5m";
            node_drain_ignore_system_jobs = "false";
            node_purge = "true";
            nomad_selector_strategy = "empty_ignore_system";
          };
        };
      };
    };
  });
in {
  environment.etc = policies;

  services.nomad-autoscaler = {
    enable = true;
    log_level = "DEBUG";
    policy.dir = "/etc/nomad-autoscaler.d/policies";
    telemetry.prometheus_metrics = true;

    nomad = {
      address = "https://127.0.0.1:4646";
      ca_cert = "/etc/ssl/certs/ca.pem";
      ca_path = "/etc/ssl/certs";
      client_cert = "/etc/ssl/certs/cert.pem";
      client_key = "/etc/ssl/certs/cert-key.pem";
    };

    apm.victoriametrics = {
      driver = "prometheus";
      config.address =
        "http://${config.cluster.instances.monitoring.privateIP}:8428";
    };

    target = lib.flip lib.mapAttrs asgs (name: asg: {
      driver = "aws-asg";
      config.aws_region = asg.region;
    });

    strategy.target-value.driver = "target-value";
  };
}

