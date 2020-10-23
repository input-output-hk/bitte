{ lib, pkgs, config, nodeName, ... }:
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
    ./secrets.nix
  ];

  services = {
    nomad.enable = false;
    vault-agent-core.enable = true;
    amazon-ssm-agent.enable = true;
    ingress.enable = true;
    seaweedfs.filer = {
      enable = true;
      s3.enable = true;

      master = lib.forEach [ "core-1" "core-2" "core-3" ] (core:
        "${config.cluster.instances.${core}.privateIP}:${
          toString config.services.seaweedfs.master.port
        }");

      peers = lib.forEach ["core-1" "core-2" "core-3"] (core:
        "${config.cluster.instances.${core}.privateIP}:${
          toString config.services.seaweedfs.filer.http.port
        }");

      postgres.enable = true;
      postgres.hostname = "${nodeName}.node.consul";
      postgres.port = 26257;
    };

    oauth2_proxy = {
      enable = true;
      extraConfig.whitelist-domain = ".${domain}";
      # extraConfig.github-org = "input-output-hk";
      # extraConfig.github-repo = "input-output-hk/mantis-ops";
      # extraConfig.github-user = "manveru,johnalotoski";
      extraConfig.pass-user-headers = "true";
      extraConfig.set-xauthrequest = "true";
      extraConfig.reverse-proxy = "true";
      provider = "google";
      keyFile = "/run/keys/oauth-secrets";

      email.domains = [ "iohk.io" ];
      cookie.domain = ".${domain}";
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
      };
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

  users.extraGroups.keys.members = [ "oauth2_proxy" ];

  secrets.install.oauth.script = ''
    export PATH="${lib.makeBinPath (with pkgs; [ sops coreutils ])}"

    cat ${config.secrets.encryptedRoot + "/oauth-secrets"} \
      | sops -d /dev/stdin \
      > /run/keys/oauth-secrets

    chown root:keys /run/keys/oauth-secrets
    chmod g+r /run/keys/oauth-secrets
  '';
}
