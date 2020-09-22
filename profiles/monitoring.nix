{ lib, pkgs, config, ... }:
let
  inherit (config.cluster) domain region instances kms;
  acme-full = "/etc/ssl/certs/${config.cluster.domain}-full.pem";
in {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./loki.nix
    ./telegraf.nix
    ./vault/client.nix
  ];

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

        backend docker
          default-server check maxconn 2000
          option httpchk HEAD /
          server docker 127.0.0.1:5000

        frontend http
          bind *:80
          acl http ssl_fc,not
          http-request redirect scheme https if http

        frontend https
          bind *:443 ssl crt ${acme-full} alpn h2,http/1.1

          acl host_docker hdr(host) -i docker.${domain}
          use_backend docker if host_docker

          default_backend grafana
      '';
    };

    victoriametrics = {
      enable = true;
      retentionPeriod = 12; # months
    };

    loki = { enable = true; };

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
            type = "loki";
            name = "Loki";
            url = "http://localhost:3100";
            jsonData.maxLines = 1000;
          }
          {
            type = "prometheus";
            name = "VictoriaMetrics";
            url = "http://localhost:8428";
          }
        ];

        dashboards = [{
          name = "provisioned";
          options.path = ./monitoring;
        }];
      };

      security = {
        adminPasswordFile = /var/lib/grafana/password;
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

  systemd.services.haproxy.serviceConfig.RestartSec = "15s";

  secrets.generate.grafana-password = ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils sops xkcdpass ])}"

    if [ ! -s encrypted/grafana-password.json ]; then
      xkcdpass \
      | sops --encrypt --kms '${kms}' /dev/stdin \
      > encrypted/grafana-password.json
    fi
  '';

  secrets.install.grafana-password.script = ''
    export PATH="${lib.makeBinPath (with pkgs; [ sops coreutils ])}"

    mkdir -p /var/lib/grafana

    cat ${config.secrets.encryptedRoot + "/grafana-password.json"} \
      | sops -d /dev/stdin \
      > /var/lib/grafana/password
  '';
}
