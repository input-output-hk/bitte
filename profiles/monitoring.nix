{ lib, pkgs, config, nodeName, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  domain =
    config.${if deployType == "aws" then "cluster" else "currentCoreNode"}.domain;
  isSops = deployType == "aws";
in {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./vault/monitoring.nix

    ./auxiliaries/builder.nix
    ./auxiliaries/docker-registry.nix
    ./auxiliaries/loki.nix
    ./auxiliaries/oauth.nix
  ];

  services.consul.ui = true;
  services.nomad.enable = false;
  services.minio.enable = true;
  services.vulnix.enable = true;
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
    domain = "monitoring.${domain}";
    extraOptions = {
      AUTH_PROXY_ENABLED = "true";
      AUTH_PROXY_HEADER_NAME = "X-Auth-Request-Email";
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

    security.adminPasswordFile = if isSops then "/var/lib/grafana/password"
                                 else config.age.secrets.grafana-password.path;
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

  secrets.generate.grafana-password = lib.mkIf isSops ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils sops xkcdpass ])}"

    if [ ! -s encrypted/grafana-password.json ]; then
      xkcdpass \
      | sops --encrypt --kms '${config.cluster.kms}' /dev/stdin \
      > encrypted/grafana-password.json
    fi
  '';

  secrets.install.grafana-password.script = lib.mkIf isSops ''
    export PATH="${lib.makeBinPath (with pkgs; [ sops coreutils ])}"

    mkdir -p /var/lib/grafana

    cat ${(toString config.secrets.encryptedRoot) + "/grafana-password.json"} \
      | sops -d /dev/stdin \
      > /var/lib/grafana/password
  '';

  age.secrets = lib.mkIf (deployType != "aws") {
    grafana-password = {
      file = config.age.encryptedRoot + "/grafana/password.age";
      path = "/var/lib/grafana/grafana-password";
      mode = "0600";
    };
  };
}
