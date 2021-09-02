{ pkgs, config, lib, ... }:
let
  inherit (config.cluster) region instances;
  inherit (lib) optional optionalAttrs;
in {
  systemd.services.telegraf.path = with pkgs; [ procps ];

  services.vulnix.sink = let
    inherit (config.services.telegraf.extraConfig.inputs.http_listener_v2)
      service_address path;
    address =
      (lib.optionalString (lib.hasPrefix ":" service_address) "127.0.0.1") +
      service_address;
  in pkgs.writeBashChecked "vulnix-telegraf" ''
    function send {
      ${pkgs.curl}/bin/curl --no-progress-meter \
        -XPOST http://${address}${path} --data-binary @- "$@"
    }

    if [[ -n "$NOMAD_JOB_NAMESPACE$NOMAD_JOB_ID$NOMAD_JOB_TASKGROUP_NAME$NOMAD_JOB_TASK_NAME" ]]; then
      send \
        -H "X-Telegraf-Tag-nomad_namespace: $NOMAD_JOB_NAMESPACE" \
        -H "X-Telegraf-Tag-nomad_job: $NOMAD_JOB_ID" \
        -H "X-Telegraf-Tag-nomad_taskgroup: $NOMAD_JOB_TASKGROUP_NAME" \
        -H "X-Telegraf-Tag-nomad_task: $NOMAD_JOB_TASK_NAME"
    else
      send
    fi
  '';

  services.telegraf = {
    enable = true;

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
              toString config.services.promtail.server.http_listen_port
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
      }) // (optionalAttrs config.services.vulnix.enable {
        http_listener_v2 = {
          service_address = ":8008";
          path = "/vulnix";
          methods = [ "POST" ];
          data_source = "body";
          http_header_tags = {
            X-Telegraf-Tag-nomad_namespace = "nomad_namespace";
            X-Telegraf-Tag-nomad_job       = "nomad_job";
            X-Telegraf-Tag-nomad_taskgroup = "nomad_taskgroup";
            X-Telegraf-Tag-nomad_task      = "nomad_task";
          };

          data_format = "json";
          tag_keys = [ "pname" "version" ];

          name_override = "vulnerability";
        };
      });

      processors.starlark = [ {
        namepass = [ "vulnerability" ];

        # XXX replace with regex processor
        # once https://github.com/influxdata/telegraf/pull/9561 is merged
        source = ''
          def apply(metric):
              for k, v in metric.fields.items():
                  if k.startswith("cvssv3_basescore_"):
                      metric.fields.pop(k)
                      metric.fields["score"] = v
                      metric.tags["cve"] = k[len("cvssv3_basescore_CVE-"):]
              return metric
        '';
      } ];

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
