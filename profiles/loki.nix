{ pkgs, lib, config, ... }: {

  # Required for Loki >= 2.3.0 ruler
  systemd.services.loki.serviceConfig.ExecStartPre =
    lib.mkIf config.services.loki.enable
      "+${pkgs.coreutils}/bin/mkdir -p /etc/loki/rules/fake";

  services.loki = {
    configuration = {
      auth_enabled = false;

      ingester = {
        chunk_idle_period = "5m";
        chunk_retain_period = "30s";
        lifecycler = {
          address = "127.0.0.1";
          final_sleep = "0s";
          ring = {
            kvstore = { store = "inmemory"; };
            replication_factor = 1;
          };
        };
      };

      limits_config = {
        enforce_metric_name = false;
        reject_old_samples = true;
        reject_old_samples_max_age = "168h";
        ingestion_rate_mb = 160;
        ingestion_burst_size_mb = 160;
      };

      schema_config = {
        configs = [{
          from = "2020-05-15";
          index = {
            period = "168h";
            prefix = "index_";
          };
          object_store = "filesystem";
          schema = "v11";
          store = "boltdb";
        }];
      };

      server = { http_listen_port = 3100; };

      storage_config = {
        boltdb = { directory = "/var/lib/loki/index"; };
        filesystem = { directory = "/var/lib/loki/chunks"; };
      };

      ruler = {
        enable_api = true;
        enable_alertmanager_v2 = true;
        ring.kvstore.store = "inmemory";
        rule_path = "/tmp/loki/rules-temp";
        storage = {
          type = "local";
          local.directory = "/etc/loki/rules";
        };
      };
    };
  };
}
