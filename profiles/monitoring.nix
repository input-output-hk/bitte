{ lib, pkgs, config, nodeName, etcEncrypted, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  domain =
    config.${if deployType == "aws" then "cluster" else "currentCoreNode"}.domain;
  isSops = deployType == "aws";
  cfg = config.services.monitoring;
  relEncryptedFolder = lib.last (builtins.split "-" (toString config.secrets.encryptedRoot));
    alertmanagerYml = if config.services.prometheus.alertmanager.configText != null then
    pkgs.writeText "alertmanager.yml" config.services.prometheus.alertmanager.configText
    else pkgs.writeText "alertmanager.yml" (builtins.toJSON config.services.prometheus.alertmanager.configuration);
in {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./vault/aux.nix

    ./auxiliaries/loki.nix

    ../modules/vault-backend.nix
  ];

  # Nix alertmanager module requires group rule syntax checking,
  # but env substitution through services.prometheus.alertmanager.environmentFile
  # requires bash variables in the group rules which will not pass syntax validation
  # in some fields, such as a url field.  This works around the problem.
  systemd.services.alertmanager.preStart = let
    cfg = config.services.prometheus.alertmanager;
    alertmanagerYml = if cfg.configText != null then
    pkgs.writeText "alertmanager.yml" cfg.configText
    else pkgs.writeText "alertmanager.yml" (builtins.toJSON cfg.configuration);
  in lib.mkForce ''
    ${pkgs.gnused}/bin/sed 's|https://deadmanssnitch.com|$DEADMANSSNITCH|g' "${alertmanagerYml}" > "/tmp/alert-manager-sed.yaml"
    ${lib.getBin pkgs.envsubst}/bin/envsubst -o "/tmp/alert-manager-substituted.yaml" \
                                             -i "/tmp/alert-manager-sed.yaml"
  '';

  options.services.monitoring = {
    useOauth2Proxy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Utilize oauth auth headers provided from traefik on routing for grafana.
        One, but not both, of `useOauth2Proxy` or `useDigestAuth` options must be true.
      '';
    };

    useDigestAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Utilize digest auth headers provided from traefik on routing for grafana.
        One, but not both, of `useOauth2Proxy` or `useDigestAuth` options must be true.
      '';
    };

    useDockerRegistry = lib.mkOption {
      type = lib.types.bool;
      default = lib.warn ''
        DEPRECATED: -- this option is now a no-op.
        To enable a docker registry, apply the following
        bitte module to the target docker registry host machine,
        and set module options appropriately:

        modules/docker-registry.nix
      '' false;
      description = ''
        DEPRECATED: -- this option is now a no-op.
        To enable a docker registry, apply the following
        bitte module to the target docker registry host machine,
        and set module options appropriately:

        modules/docker-registry.nix
      '';
    };

    useVaultBackend = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable use of a vault TF backend with a service hosted on the monitoring server.
      '';
    };

  };

  config = {

    assertions = [
      {
        assertion = cfg.useOauth2Proxy != cfg.useDigestAuth;
        message = ''
          Both `useOauth2Proxy` and `useDigestAuth` options cannot be enabled at the same time.
          One of `useOauth2Proxy` and `useDigestAuth` options must be enabled.
        '';
      }
    ];

    networking.firewall.allowedTCPPorts = [
      config.services.grafana.port
      8428  # victoriaMetrics
      9000  # minio
    ];

    services.consul.ui = true;
    services.nomad.enable = false;
    services.minio.enable = true;
    services.victoriametrics.enable = true;
    services.loki.enable = true;
    services.grafana.enable = true;
    services.prometheus.enable = false;
    services.vault-backend.enable = cfg.useVaultBackend;
    # services.vulnix.enable = true;
    # services.vulnix.scanClosure = true;

    services.victoriametrics = {
      retentionPeriod = 12; # months
    };

    # Avoid monitor alerting failures due to default service nofile limit of 1024
    systemd.services.victoriametrics.serviceConfig.LimitNOFILE = 65535;
    service.vmagent = {
      enable = true;
      httpPathPrefix = "/vmagent";
      promscrapeConfig = [
        (lib.mkIf config.services.vmagent.enable {
          job_name = "vmagent";
          scrape_interval = "60s";
          metrics_path = "${config.services.vmagent.httpPathPrefix}/metrics";
          static_configs = [{
            targets = [ "${config.services.vmagent.httpListenAddr}" ];
            labels = { alias = "vmagent"; };
          }];
        })
        (lib.mkIf config.services.vmalert.enable {
          job_name = "vmalert";
          scrape_interval = "60s";
          metrics_path = "${config.services.vmalert.httpPathPrefix}/metrics";
          static_configs = [{
            targets = [ "${config.services.vmalert.httpListenAddr}" ];
            labels = { alias = "vmalert"; };
          }];
        })
      ];
    };
    services.vmalert = {
      enable = true;
      externalUrl = "https://monitoring.${domain}/vmalert";
      httpPathPrefix = "/vmalert";
      rules = (import ./monitoring/alerts/alerts.nix "https://monitoring.${domain}").groups;
    };

    loki = { enable = true; };

    services.grafana = {
      auth.anonymous.enable = false;
      analytics.reporting.enable = false;
      addr = "";
      domain = "monitoring.${domain}";
      extraOptions = {
        AUTH_PROXY_ENABLED = "true";
        USERS_AUTO_ASSIGN_ORG_ROLE = "Editor";
        # Enable next generation alerting for >= 8.2.x
        UNIFIED_ALERTING_ENABLED = "true";
        ALERTING_ENABLED = "false";
      } // lib.optionalAttrs cfg.useOauth2Proxy {
        AUTH_PROXY_HEADER_NAME = "X-Auth-Request-Email";
        AUTH_SIGNOUT_REDIRECT_URL = "/oauth2/sign_out";
      } // lib.optionalAttrs cfg.useDigestAuth {
        AUTH_PROXY_HEADER_NAME = "X-WebAuth-User";
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
          options.path = ./monitoring/dashboards;
        }];
      };

      security.adminPasswordFile = if isSops then "/var/lib/grafana/password"
                                  else config.age.secrets.grafana-password.path;
    };

    services.prometheus = {
      alertmanagers = [{
        scheme = "http";
        path_prefix = "/";
        static_configs = [{ targets = [ "localhost:9093" ]; }];
      }];

      alertmanager = {
        enable = true;
        environmentFile = "/run/keys/alertmanager";
        listenAddress = "localhost";
        webExternalUrl = "https://monitoring.${domain}/alertmanager";
        configuration = {
          route = {
            group_by = [ "alertname" "alias" ];
            group_wait = "30s";
            group_interval = "2m";
            receiver = "team-pager";
            routes = [
              {
                match = { severity = "page"; };
                receiver = "team-pager";
              }
              {
                match = { alertname = "DeadMansSnitch"; };
                repeat_interval = "5m";
                receiver = "deadmanssnitch";
              }
            ];
          };
          receivers = [
            {
              name = "team-pager";
              pagerduty_configs = [
                {
                  service_key = "$PAGERDUTY";
                }
              ];
            }
            {
              name = "deadmanssnitch";
              webhook_configs = [
                {
                  send_resolved = false;
                  url = "https://deadmanssnitch.com";
                }
              ];
            }
          ];
        };
      };

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

      if [ ! -s ${relEncryptedFolder}/grafana-password.json ]; then
        xkcdpass \
        | sops --encrypt --kms '${config.cluster.kms}' /dev/stdin \
        > ${relEncryptedFolder}/grafana-password.json
      fi
    '';

    secrets.install.grafana-password.script = lib.mkIf isSops ''
      export PATH="${lib.makeBinPath (with pkgs; [ sops coreutils ])}"

      mkdir -p /var/lib/grafana

      cat ${etcEncrypted}/grafana-password.json \
        | sops -d /dev/stdin \
        > /var/lib/grafana/password
    '';

    age.secrets = lib.mkIf (deployType != "aws") {
      grafana-password = {
        file = config.age.encryptedRoot + "/grafana/password.age";
        path = "/var/lib/grafana/grafana-password";
        owner = "grafana";
        group = "grafana";
        mode = "0600";
      };
    };
  };
}
