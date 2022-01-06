{ lib, pkgs, config, nodeName, ... }: {
  imports = [
    ./common.nix
    ./consul/client.nix

    ./auxiliaries/builder.nix
    ./auxiliaries/docker-registry.nix
    ./auxiliaries/loki.nix
    ./auxiliaries/oauth.nix
  ];

  services.consul.ui = true;
  services.nomad.enable = false;
  services.ingress.enable = true;
  services.ingress-config.enable = true;
  services.minio.enable = true;
  services.vulnix.enable = true;
  services.vault-agent-monitoring.enable = true;
  services.victoriametrics.enable = true;
  services.loki.enable = true;
  services.grafana.enable = true;
  services.prometheus.enable = false;
  services.vulnix.scanClosure = true;

  services.victoriametrics = {
    retentionPeriod = 12; # months
  };

  services.grafana = {
    auth.anonymous.enable = false;
    analytics.reporting.enable = false;
    addr = "";
    domain = "monitoring.${config.cluster.domain}";
    extraOptions = {
      AUTH_PROXY_ENABLED = "true";
      AUTH_PROXY_HEADER_NAME = "X-Authenticated-User";
      AUTH_SIGNOUT_REDIRECT_URL = "/oauth2/sign_out";
      USERS_AUTO_ASSIGN_ORG_ROLE = "Editor";
    };
    rootUrl = "https://monitoring.${config.cluster.domain}/";
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

    security.adminPasswordFile = /var/lib/grafana/password;
  };

  services.prometheus = {
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

  secrets.generate.grafana-password = ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils sops xkcdpass ])}"

    if [ ! -s encrypted/grafana-password.json ]; then
      xkcdpass \
      | sops --encrypt --kms '${config.cluster.kms}' /dev/stdin \
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

  services.vault-agent = {
    templates = let
      command =
        "${pkgs.systemd}/bin/systemctl try-restart --no-block ingress.service";
    in {
      "/etc/ssl/certs/${config.cluster.domain}-cert.pem" = {
        contents = ''
          {{ with secret "kv/bootstrap/letsencrypt/cert" }}{{ .Data.data.value }}{{ end }}
        '';
        inherit command;
      };

      "/etc/ssl/certs/${config.cluster.domain}-full.pem" = {
        contents = ''
          {{ with secret "kv/bootstrap/letsencrypt/fullchain" }}{{ .Data.data.value }}{{ end }}
        '';
        inherit command;
      };

      "/etc/ssl/certs/${config.cluster.domain}-key.pem" = {
        contents = ''
          {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
        '';
        inherit command;
      };

      "/etc/ssl/certs/${config.cluster.domain}-full.pem.key" = {
        contents = ''
          {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
        '';
        inherit command;
      };
    };
  };
}
