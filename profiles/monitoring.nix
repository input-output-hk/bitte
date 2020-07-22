{ pkgs, config, ... }:
let inherit (config.cluster) domain region instances;
in {
  imports =
    [ ./common.nix ./consul/client.nix ./vault/client.nix ./telegraf.nix ];

  services = {
    nomad.enable = false;
    vault-agent-core.enable = true;
    amazon-ssm-agent.enable = true;

    haproxy = {
      enable = true;
      config = ''
        global
          log /dev/log local0 info

        defaults
          log global
          mode http
          option httplog
          option dontlognull
          timeout connect 5000
          timeout client 50000
          timeout server 50000
          default-server init-addr none
          balance roundrobin

        backend grafana
          default-server check maxconn 2000
          server grafana 127.0.0.1:3000

        frontend http
          bind *:80
          default_backend grafana
      '';
    };

    victoriametrics = {
      enable = true;
      retentionPeriod = 12;
    };

    influxdb = { enable = true; };

    grafana = {
      enable = true;
      auth.anonymous.enable = false;
      analytics.reporting.enable = false;
      addr = "";
      domain = "monitoring.${domain}";
      # rootUrl = "%(protocol)s://%(domain)s/grafana/";
      provision = {
        enable = true;

        datasources = [
          {
            type = "prometheus";
            name = "victoriametrics";
            url = "http://localhost:8428";
          }
          {
            type = "influxdb";
            name = "telegraf";
            database = "telegraf";
            url = "http://localhost:8086";
          }
        ];
      };

      security = {
        adminPassword = "finalist superjet unlinked delay stinking hubcap";
      };
    };

    prometheus = {
      exporters = {
        blackbox = {
          enable = true;
          configFile = pkgs.toPrettyJSON "blackbox-exporter" {
            modules = {
              https_2xx = {
                prober = "http";
                timeout = "5s";
                http = { fail_if_not_ssl = true; };
              };
            };
          };
        };
      };
    };
  };
}
