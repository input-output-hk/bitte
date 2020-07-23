{ pkgs, lib, config, ... }:
let
  inherit (lib) mkIf mkEnableOption mkOption;
  inherit (lib.types) undefined attrsOf;
  cfg = config.services.promtail;

  configJson = pkgs.toPrettyJSON "promtail" {
    server = {
      grpc_listen_port = 0;
      http_listen_port = 3101;
    };

    clients = [{
      url =
        "http://${config.cluster.instances.monitoring.privateIP}:3100/loki/api/v1/push";
    }];

    positions = { filename = "/var/lib/promtail/positions.yaml"; };

    scrape_configs = [
      {
        ec2_sd_configs = [{ region = config.cluster.region; }];

        job_name = "ec2-logs";

        relabel_configs = [
          {
            action = "replace";
            source_labels = [ "__meta_ec2_tag_Name" ];
            target_label = "name";
          }
          {
            action = "replace";
            source_labels = [ "__meta_ec2_instance_id" ];
            target_label = "instance";
          }
          {
            action = "replace";
            source_labels = [ "__meta_ec2_availability_zone" ];
            target_label = "zone";
          }
          {
            action = "replace";
            replacement = "/var/log/**.log";
            target_label = "__path__";
          }
          {
            regex = "(.*)";
            source_labels = [ "__meta_ec2_private_dns_name" ];
            target_label = "__host__";
          }
        ];
      }
      {
        job_name = "journal";
        journal = {
          json = false;
          labels = {
            job = "systemd-journal";
            region = config.cluster.region;
          };
          max_age = "12h";
          path = "/var/log/journal";
        };
        relabel_configs = [
          {
            source_labels = [ "__journal__systemd_unit" ];
            target_label = "unit";
          }
          {
            source_labels = [ "__journal__hostname" ];
            target_label = "host";
          }
        ];
      }
    ];
  };
in {
  options = {
    services.promtail = {
      enable = mkEnableOption "Enable Promtail";
      config = mkOption {
        type = attrsOf undefined;
        default = { };
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.promtail = {
      description = "Promtail service for Loki";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart =
          "${pkgs.grafana-loki}/bin/promtail --config.file ${configJson}";
        Restart = "on-failure";
        RestartSec = "20s";
        SuccessExitStatus = 143;
        StateDirectory = "promtail";
        # DynamicUser = true;
        # User = "promtail";
        # Group = "promtail";
      };
    };
  };
}
