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
          lua-prepend-path ${pkgs.haproxy-auth-request}/usr/share/haproxy/?/http.lua
          lua-prepend-path ${pkgs.lua53Packages.dkjson}/share/lua/5.3/dk?.lua
          lua-load ${pkgs.haproxy-auth-request}/usr/share/haproxy/auth-request.lua

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

        backend oauth_proxy
          mode http
          server auth_request 127.0.0.1:4180 check

        frontend http
          bind *:80
          acl http ssl_fc,not
          http-request redirect scheme https if http

        frontend https
          bind *:443 ssl crt ${acme-full} alpn h2,http/1.1

          acl oauth_proxy path_beg /oauth2/

          http-request lua.auth-request oauth_proxy /oauth2/auth

          use_backend oauth_proxy if ! { var(txn.auth_response_successful) -m bool }
          use_backend oauth_proxy if oauth_proxy

          http-request add-header X-Authenticated-User %[var(req.auth_response_header.x_auth_request_email)]

          default_backend grafana
      '';
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

      email.domains = ["iohk.io"];
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
