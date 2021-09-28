{ lib, pkgs, config, nodeName, ... }:
let inherit (config.cluster) domain region instances kms;
in {
  imports = [
    ./builder.nix
    ./common.nix
    ./consul/client.nix
    ./docker-registry.nix
    ./loki.nix
    ./oauth.nix
    ./telegraf.nix
  ];

  age.secrets.grafana-password.file = config.age.encryptedRoot
    + "/grafana/password.age";

  services = {
    vault.enable = lib.mkForce false;
    consul.ui = true;
    nomad.enable = false;
    ingress.enable = true;
    ingress-config.enable = true;
    minio.enable = true;

    vault-agent-core = {
      enable = true;
      vaultAddress = "https://core-1:8200";
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

      security.adminPasswordFile = config.age.secrets.grafana-password.path;
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
