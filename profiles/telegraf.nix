{ pkgs, config, lib, ... }:
let
  inherit (config.cluster) region instances;
  inherit (lib) optional optionalAttrs;
in {
  systemd.services.telegraf.path = with pkgs; [ procps ];

  services.telegraf = {
    enable = lib.mkDefault true;

    extraConfig = {
      agent = {
        interval = "10s";
        flush_interval = "10s";
        omit_hostname = false;

        ## Telegraf will send metrics to outputs in batches of at most
        ## metric_batch_size metrics.
        ## This controls the size of writes that Telegraf sends to output plugins.
        metric_batch_size = 5000;

        ## Maximum number of unwritten metrics per output.  Increasing this value
        ## allows for longer periods of output downtime without dropping metrics at the
        ## cost of higher maximum memory usage.
        metric_buffer_limit = 50000;
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

        prometheus = let
          promtail = "http://127.0.0.1:${
              toString config.services.promtail.configuration.server.http_listen_port
            }/metrics";
          autoscaling = "http://127.0.0.1:${
              toString config.services.nomad-autoscaler.http.bind_port
            }/v1/metrics?format=prometheus";
          loki = "http://127.0.0.1:${
              toString
              config.services.loki.configuration.server.http_listen_port
            }/metrics";
        in {
          urls = optional config.services.promtail.enable promtail
            ++ optional config.services.loki.enable loki
            ++ optional config.services.nomad-autoscaler.enable autoscaling;
          metric_version = 2;
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
          urls = [ "http://monitoring:8428" ];
        };
      };
    };
  };
}
