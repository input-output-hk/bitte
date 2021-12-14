{ lib, pkgs, config, nodeName, ... }:
let
  inherit (config.cluster) domain region instances kms;
  acme-full = "/etc/ssl/certs/${config.cluster.domain}-full.pem";
in {
  imports = [
    ./builder.nix
    ./common.nix
    ./consul/client.nix
    ./docker-registry.nix
    ./loki.nix
    ./oauth.nix
    ./secrets.nix
    ./telegraf.nix
    ./vault/client.nix
  ];

  services = {
    consul.ui = true;
    nomad.enable = false;
    ingress.enable = true;
    ingress-config.enable = true;
    minio.enable = true;
    vulnix = {
      enable = true;
      scanClosure = true;
    };

    vault-agent-monitoring.enable = true;

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
      extraOptions = {
        AUTH_PROXY_ENABLED = "true";
        AUTH_PROXY_HEADER_NAME = "X-Authenticated-User";
        AUTH_SIGNOUT_REDIRECT_URL = "/oauth2/sign_out";
        USERS_AUTO_ASSIGN_ORG_ROLE = "Editor";
      };
      rootUrl = "https://monitoring.${domain}/";
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

      security = { adminPasswordFile = /var/lib/grafana/password; };
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
