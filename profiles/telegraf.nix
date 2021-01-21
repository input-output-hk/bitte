{ pkgs, config, lib, ... }:
let
  inherit (config.cluster) region instances;
  inherit (lib) optional optionalAttrs;
in {
  systemd.services.telegraf.path = with pkgs; [ procps ];

  services.telegraf = {
    enable = true;

    extraConfig = {
      agent = {
        interval = "10s";
        flush_interval = "10s";
        omit_hostname = false;
      };

      global_tags = { datacenter = region; };

      inputs = {
        statsd = {
          protocol = "udp";
          service_address = ":8125";
          delete_gauges = true;
          delete_counters = true;
          delete_sets = true;
          delete_timings = true;
          percentiles = [ 90 ];
          metric_separator = "_";
          datadog_extensions = true;
          allowed_pending_messages = 10000;
          percentile_limit = 1000;
        };

        prometheus = {
          #urls = [ "http://127.0.0.1:3101/metrics" "http://127.0.0.1:9334" ];
          urls = [ "http://127.0.0.1:3101/metrics" ]
            ++ optional config.services.loki.enable
            "http://127.0.0.1:3100/metrics";
          metric_version = 1;
        };

        cpu = {
          percpu = true;
          totalcpu = true;
          collect_cpu_time = false;
        };

        disk = { };
        # mount_points = ["/"]
        # ignore_fs = ["tmpfs", "devtmpfs"]

        diskio = { };
        # devices = ["sda", "sdb"]
        # skip_serial_number = false

        systemd_units = { unittype = "service"; };

        x509_cert = { sources = [ "/etc/ssl/certs/cert.pem" ]; };

        kernel = { };
        linux_sysctl_fs = { };
        mem = { };
        net = { interfaces = [ "en*" ]; };
        netstat = { };
        processes = { };
        swap = { };
        system = { };
        procstat = { pattern = "(consul)"; };
        consul = {
          address = "localhost:8500";
          scheme = "http";
        };
      } // (optionalAttrs config.services.ingress.enable {
        haproxy = { servers = [ "http://127.0.0.1:1936/haproxy?stats" ]; };
      });

      # Store data in VictoriaMetrics
      outputs = {
        influxdb = {
          database = "telegraf";
          urls = [ "http://${instances.monitoring.privateIP}:8428" ];
        };
      };
    };
  };
}
