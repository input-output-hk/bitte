{
  lib,
  pkgs,
  config,
  nodeName,
  etcEncrypted,
  ...
}: let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  domain =
    config
    .${
      if deployType == "aws"
      then "cluster"
      else "currentCoreNode"
    }
    .domain;
  isSops = deployType == "aws";
  cfg = config.services.monitoring;

  relEncryptedFolder = let
    encPathStr =
      if isSops
      then (toString config.secrets.encryptedRoot)
      else (toString config.age.encryptedRoot);
  in
    lib.last (builtins.split "/nix/store/.{32}-" encPathStr);

  alertmanagerYml =
    if config.services.prometheus.alertmanager.configText != null
    then pkgs.writeText "alertmanager.yml" config.services.prometheus.alertmanager.configText
    else pkgs.writeText "alertmanager.yml" (builtins.toJSON config.services.prometheus.alertmanager.configuration);
in {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./vault/monitoring.nix

    ./auxiliaries/loki.nix

    ../modules/vault-backend.nix
  ];

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
      default =
        lib.warn ''
          DEPRECATED: -- this option is now a no-op.
          To enable a docker registry, apply the following
          bitte module to the target docker registry host machine,
          and set module options appropriately:

          modules/docker-registry.nix
        ''
        false;
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
      config.services.grafana.port # default: 3000
      8428 # victoriaMetrics
      8429 # vmagent
      8880 # vmalert-vm
      8881 # vmalert-loki
      9000 # minio
      9093 # alertmanager
    ];

    services.consul.ui = true;
    services.nomad.enable = false;
    services.minio.enable = true;
    services.victoriametrics.enable = true;
    services.victoriametrics.enableVmalertProxy = true;
    services.loki.enable = true;
    services.grafana.enable = true;
    services.prometheus.enable = false;

    services.tempo = {
      enable = true;
      settings = {
        server = {
          http_listen_address = "0.0.0.0";
          http_listen_port = 3200;
          grpc_listen_port = 9096;
        };
        distributor = {
          receivers = {
            otlp.protocols.grpc = null;
            otlp.protocols.http = null;
            jaeger.protocols.thrift_http = null;
            jaeger.protocols.grpc = null;
            jaeger.protocols.thrift_binary = null;
            jaeger.protocols.thrift_compact = null;
            zipkin = null;
            opencensus = null;
            # Kafka default receiver config fails is kafka is not present
            # kafka = null;
          };
        };
        ingester.lifecycler.ring.replication_factor = 3;
        # metrics_generator
        # query_frontend
        # querier
        # compactor
        storage.trace = {
          backend = "local";
          local.path = "/tmp/tempo/blocks";
          wal.path = "/tmp/tempo/wal";
        };
        search_enabled = true;
      };
    };

    services.vault-backend.enable = cfg.useVaultBackend;
    # services.vulnix.enable = true;
    # services.vulnix.scanClosure = true;

    # Nix alertmanager module requires group rule syntax checking,
    # but env substitution through services.prometheus.alertmanager.environmentFile
    # requires bash variables in the group rules which will not pass syntax validation
    # in some fields, such as a url field.  This works around the problem.
    # Ref: https://github.com/prometheus/alertmanager/issues/504
    systemd.services.alertmanager.preStart = let
      cfg = config.services.prometheus.alertmanager;
      alertmanagerYml =
        if cfg.configText != null
        then pkgs.writeText "alertmanager.yml" cfg.configText
        else pkgs.writeText "alertmanager.yml" (builtins.toJSON cfg.configuration);
    in
      lib.mkForce ''
        ${pkgs.gnused}/bin/sed 's|https://deadmanssnitch.com|$DEADMANSSNITCH|g' "${alertmanagerYml}" > "/tmp/alert-manager-sed.yaml"
        ${lib.getBin pkgs.envsubst}/bin/envsubst  -o "/tmp/alert-manager-substituted.yaml" \
                                                  -i "/tmp/alert-manager-sed.yaml"
      '';

    services.victoriametrics = {
      retentionPeriod = 12; # months
    };

    services.grafana = {
      auth.anonymous.enable = false;
      analytics.reporting.enable = false;
      addr = "";
      domain = "monitoring.${domain}";
      extraOptions =
        {
          AUTH_PROXY_ENABLED = "true";
          USERS_AUTO_ASSIGN_ORG_ROLE = "Editor";
          # Enable next generation alerting for >= 8.2.x
          UNIFIED_ALERTING_ENABLED = "true";
          ALERTING_ENABLED = "false";
        }
        // lib.optionalAttrs cfg.useOauth2Proxy {
          AUTH_PROXY_HEADER_NAME = "X-Auth-Request-Email";
          AUTH_SIGNOUT_REDIRECT_URL = "/oauth2/sign_out";
        }
        // lib.optionalAttrs cfg.useDigestAuth {
          AUTH_PROXY_HEADER_NAME = "X-WebAuth-User";
        };
      rootUrl = "https://monitoring.${domain}/";
      provision = {
        enable = true;
        datasources = [
          {
            type = "loki";
            name = "Loki";
            # Here we point the datasource for Loki to an nginx
            # reverse proxy to intercept prometheus rule api
            # calls so that vmalert handler for declarative loki
            # alerts can respond, thereby allowing grafana to
            # display them in the next generation alerting interface.
            # The actual loki service still exists at the standard port.
            url = "http://127.0.0.1:3099";
            jsonData.maxLines = 1000;
          }
          {
            type = "prometheus";
            name = "VictoriaMetrics";
            url = "http://127.0.0.1:8428";
          }
        ];

        dashboards = [
          {
            name = "tf-declared-dashboards";
            options.path = "/var/lib/grafana/dashboards";
          }
        ];
      };

      security.adminPasswordFile =
        if isSops
        then "/var/lib/grafana/password"
        else config.age.secrets.grafana-password.path;
    };

    # While victoriametrics offers a -vmalert.proxyURL option to forward grafana
    # rule requests to the vmalert API, there is no such corresponding option
    # to forward Loki rules requests to the vmalert handling declarative alerts for Loki.
    # In this case, we can intercept Grafana's request for Loki alert rules
    # and redirect the request to the appropriate vmalert.
    services.nginx = {
      enable = true;
      logError = "stderr debug";
      commonHttpConfig = ''
        log_format myformat '$remote_addr - $remote_user [$time_local] '
                            '"$request" $status $body_bytes_sent '
                            '"$http_referer" "$http_user_agent"';
      '';
      recommendedProxySettings = true;
      upstreams.loki = {
        servers = {"127.0.0.1:3100" = {};};
        extraConfig = ''
          keepalive 16;
        '';
      };
      virtualHosts."127.0.0.1" = let
        cfg = config.services.vmalert.datasources.loki;
      in {
        listen = [
          {
            addr = "0.0.0.0";
            port = 3099;
          }
        ];
        locations = {
          "/" = {
            proxyPass = "http://loki";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Connection "Keep-Alive";
              proxy_set_header Proxy-Connection "Keep-Alive";
              proxy_read_timeout 600;
            '';
          };
          "/prometheus/api/v1/rules" = {
            proxyPass = "http://${cfg.httpListenAddr}${cfg.httpPathPrefix}/api/v1/rules";
          };
        };
      };
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
                http = {fail_if_not_ssl = true;};
              };
            };
          };
        };
      };

      alertmanagers = [
        {
          scheme = "http";
          path_prefix = "/";
          static_configs = [{targets = ["127.0.0.1:9093"];}];
        }
      ];

      alertmanager = {
        enable = true;
        environmentFile = "/run/keys/alertmanager";
        listenAddress = "0.0.0.0";
        webExternalUrl = "https://monitoring.${domain}/alertmanager";
        configuration = {
          route = {
            group_by = ["..."];
            group_wait = "30s";
            group_interval = "2m";
            receiver = "team-pager";
            routes = [
              {
                match = {severity = "page";};
                receiver = "team-pager";
              }
              {
                match = {alertname = "DeadMansSnitch";};
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
                  # We actually need a $DEADMANSSNITCH var here, but the syntax
                  # checking as part of the build won't allow it on a url type.
                  # Therefore, we resort to the script above for:
                  # systemd.services.alertmanager.preStart.
                  url = "https://deadmanssnitch.com";
                }
              ];
            }
          ];
        };
      };
    };

    # Vmagent is used to scrape itself as well as vmalert service, provide a domain
    # specific interactive webUI and is already a part of the victoriametrics package.
    services.vmagent = {
      enable = true;
      httpListenAddr = "0.0.0.0:8429";
      httpPathPrefix = "/vmagent";
      promscrapeConfig =
        [
          (lib.mkIf config.services.vmagent.enable {
            job_name = "vmagent";
            scrape_interval = "60s";
            metrics_path = "${config.services.vmagent.httpPathPrefix}/metrics";
            static_configs = [
              {
                targets = [config.services.vmagent.httpListenAddr];
                labels.alias = "vmagent";
              }
            ];
          })
        ]
        ++ lib.optionals config.services.vmalert.enable (builtins.attrValues (
          # Add a vmagent target scrape for each services.vmalert.datasources attr
          lib.mapAttrs (name: cfgDs: {
            job_name = "vmalert-${name}";
            scrape_interval = "60s";
            metrics_path = "${cfgDs.httpPathPrefix}/metrics";
            static_configs = [
              {
                targets = [cfgDs.httpListenAddr];
                labels.alias = name;
              }
            ];
          })
          config.services.vmalert.datasources
        ));
    };

    services.vmalert = {
      enable = true;
      datasources = {
        # For externalAlertSource attrs, these are set to allow creation of clickable source links directly from pagerduty alerts.
        # Partial url escaping is required to avoid pagerDuty link breakage and grafana link function.
        # Trigger expression is vmalert template interpolated and escaped.  Systemd requires further escaping % chars as %%.
        vm = {
          datasourceUrl = "http://127.0.0.1:8428";
          httpListenAddr = "0.0.0.0:8880";
          externalUrl = "https://monitoring.${domain}";
          httpPathPrefix = "/vmalert-vm";
          externalAlertSource = ''explore?left=%%7B%%22datasource%%22:%%22VictoriaMetrics%%22,%%22queries%%22:%%5B%%7B%%22refId%%22:%%22A%%22,%%22expr%%22:%%22{{$expr|quotesEscape|crlfEscape|pathEscape}}%%22,%%22range%%22:true,%%22editorMode%%22:%%22code%%22%%7D%%5D,%%22range%%22:%%7B%%22from%%22:%%22now-1h%%22,%%22to%%22:%%22now%%22%%7D%%7D&orgId=1'';
        };
        loki = {
          datasourceUrl = "http://127.0.0.1:3100/loki";
          httpListenAddr = "0.0.0.0:8881";
          externalUrl = "https://monitoring.${domain}";
          httpPathPrefix = "/vmalert-loki";
          externalAlertSource = ''explore?left=%%7B%%22datasource%%22:%%22Loki%%22,%%22queries%%22:%%5B%%7B%%22refId%%22:%%22A%%22,%%22expr%%22:%%22{{$expr|quotesEscape|crlfEscape|pathEscape}}%%22,%%22range%%22:true,%%22editorMode%%22:%%22code%%22%%7D%%5D,%%22range%%22:%%7B%%22from%%22:%%22now-1h%%22,%%22to%%22:%%22now%%22%%7D%%7D&orgId=1'';
          # Loki uses PromQL type queries that do not strictly comply with PromQL
          # Ref: https://github.com/VictoriaMetrics/VictoriaMetrics/issues/780
          ruleValidateExpressions = false;
        };
      };
    };

    secrets = lib.mkIf isSops {
      generate.grafana-password = ''
        export PATH="${lib.makeBinPath (with pkgs; [coreutils sops xkcdpass])}"

        if [ ! -s ${relEncryptedFolder}/grafana-password.json ]; then
          xkcdpass \
          | sops --encrypt --kms '${config.cluster.kms}' /dev/stdin \
          > ${relEncryptedFolder}/grafana-password.json
        fi
      '';

      install.alertmanager = {
        inputType = "binary";
        outputType = "binary";
        source = config.secrets.encryptedRoot + "/alertmanager";
        target = /run/keys/alertmanager;
        script = ''
          chmod 0600 /run/keys/alertmanager
          chown alertmanager:alertmanager /run/keys/alertmanager
        '';
        #  # File format for alertmanager secret file
        #  DEADMANSSNITCH="$SECRET_ENDPOINT"
        #  PAGERDUTY="$SECRET_KEY"
      };

      install.grafana-password.script = ''
        export PATH="${lib.makeBinPath (with pkgs; [sops coreutils])}"

        mkdir -p /var/lib/grafana

        cat ${etcEncrypted}/grafana-password.json \
          | sops -d /dev/stdin \
          > /var/lib/grafana/password
      '';
    };

    age.secrets = lib.mkIf (deployType != "aws") {
      alertmanager = {
        file = config.age.encryptedRoot + "/monitoring/alertmanager.age";
        path = "/run/keys/alertmanager";
        owner = "alertmanager";
        group = "alertmanager";
        mode = "0600";
        #  # File format for alertmanager secret file
        #  DEADMANSSNITCH="$SECRET_ENDPOINT"
        #  PAGERDUTY="$SECRET_KEY"
      };

      grafana-password = {
        file = config.age.encryptedRoot + "/monitoring/grafana.age";
        path = "/var/lib/grafana/grafana-password";
        owner = "grafana";
        group = "grafana";
        mode = "0600";
      };
    };
  };
}
