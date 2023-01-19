{
  lib,
  pkgs,
  config,
  nodeName,
  etcEncrypted,
  runKeyMaterial,
  pkiFiles,
  ...
}: let
  inherit
    (lib)
    getBin
    last
    makeBinPath
    mapAttrs
    mkEnableOption
    mkForce
    mkIf
    mkOption
    optionalAttrs
    optionals
    warn
    ;

  inherit
    (lib.types)
    attrs
    bool
    ;

  inherit (pkiFiles) caCertFile;

  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  domain =
    config
    .${
      if builtins.elem deployType ["aws" "awsExt"]
      then "cluster"
      else "currentCoreNode"
    }
    .domain;
  isSops = builtins.elem deployType ["aws" "awsExt"];
  cfg = config.services.monitoring;

  relEncryptedFolder = let
    encPathStr =
      if isSops
      then (toString config.secrets.encryptedRoot)
      else (toString config.age.encryptedRoot);
  in
    last (builtins.split "/nix/store/.{32}-" encPathStr);

  alertmanagerYml =
    if config.services.prometheus.alertmanager.configText != null
    then pkgs.writeText "alertmanager.yml" config.services.prometheus.alertmanager.configText
    else pkgs.writeText "alertmanager.yml" (builtins.toJSON config.services.prometheus.alertmanager.configuration);
in {
  imports = [
    ./caddy.nix
    ./victoriametrics.nix
    ./vault-backend.nix
  ];

  options.services.monitoring = {
    enable = mkEnableOption "Enable monitoring.";

    useOauth2Proxy = mkOption {
      type = bool;
      default = true;
      description = ''
        Utilize oauth auth headers provided from traefik on routing for grafana.
        One, but not both, of `useOauth2Proxy` or `useDigestAuth` options must be true.
      '';
    };

    useDigestAuth = mkOption {
      type = bool;
      default = false;
      description = ''
        Utilize digest auth headers provided from traefik on routing for grafana.
        One, but not both, of `useOauth2Proxy` or `useDigestAuth` options must be true.
      '';
    };

    useDockerRegistry = mkOption {
      type = bool;
      default =
        warn ''
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

    useTempo = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable the use of a Grafana Tempo datasource when run as a bitte-cell Nomad
        job in the cluster.
      '';
    };

    useVaultBackend = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable use of a vault TF backend with a service hosted on the monitoring server.
      '';
    };
  };

  config = mkIf cfg.enable {
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
      3100 # loki
      8428 # victoriaMetrics
      8429 # vmagent
      8880 # vmalert-vm
      8881 # vmalert-loki
      9000 # minio
      9093 # alertmanager
    ];

    services.victoriametrics.enable = true;
    services.victoriametrics.enableVmalertProxy = true;
    services.grafana.enable = true;
    services.prometheus.enable = false;

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
      mkForce ''
        ${pkgs.gnused}/bin/sed 's|https://deadmanssnitch.com|$DEADMANSSNITCH|g' "${alertmanagerYml}" > "/tmp/alert-manager-sed.yaml"
        ${getBin pkgs.envsubst}/bin/envsubst  -o "/tmp/alert-manager-substituted.yaml" \
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
        // optionalAttrs cfg.useOauth2Proxy {
          AUTH_PROXY_HEADER_NAME = "X-Auth-Request-Email";
          AUTH_SIGNOUT_REDIRECT_URL = "/oauth2/sign_out";
        }
        // optionalAttrs cfg.useDigestAuth {
          AUTH_PROXY_HEADER_NAME = "X-WebAuth-User";
        }
        // optionalAttrs cfg.useTempo {
          # Utilize caddy for LB to OTLP SRV backends
          TRACING_OPENTELEMETRY_JAEGER_ADDRESS = "http://127.0.0.1:3098/tempo-jaeger-thrift-http/api/traces?format=jaeger.thrift";
          FEATURE_TOGGLES_ENABLE = "tempoApmTable,traceToMetrics";
        };
      rootUrl = "https://monitoring.${domain}/";
      provision = {
        enable = true;
        datasources =
          [
            (lib.recursiveUpdate {
                type = "loki";
                name = "Loki";
                uid = "Loki";
                # Here we point the datasource for Loki to a caddy
                # reverse proxy to intercept prometheus rule api
                # calls so that vmalert handler for declarative loki
                # alerts can respond, thereby allowing grafana to
                # display them in the next generation alerting interface.
                # The actual loki service still exists at the standard port.
                url = "http://127.0.0.1:3099";
                jsonData.maxLines = 1000;
              } (lib.optionalAttrs cfg.useTempo {
                jsonData.derivedFields = [
                  {
                    # Regex covers common examples of:
                    #  traceID        # casing
                    #  trace_id       # underscoring
                    #  traceId":"     # json
                    #  trace_id\":\"  # escaped json
                    matcherRegex = "trace_?[iI][dD][=,\\\\:\"]+(\\w+)";
                    name = "TraceID";
                    datasourceUid = "Tempo";
                    url = "$${__value.raw}";
                  }
                ];
              }))
            {
              type = "prometheus";
              name = "VictoriaMetrics";
              uid = "VictoriaMetrics";
              url = "http://127.0.0.1:8428";
            }
          ]
          ++ lib.optionals cfg.useTempo [
            {
              type = "tempo";
              name = "Tempo";
              uid = "Tempo";
              # Utilize caddy for LB to Tempo SRV backends
              url = "http://127.0.0.1:3098/tempo/";
              jsonData = {
                httpMethod = "GET";
                nodeGraph.enabled = true;
                lokiSearch.datasourceUid = "Loki";
                search.hide = false;
                serviceMap.datasourceUid = "VictoriaMetrics";
                tracesToLogs = {
                  datasourceUid = "Loki";
                  filterBySpanID = false;
                  filterByTraceID = false;
                  mappedTags = [
                    {
                      key = "service.name";
                      value = "service";
                    }
                  ];
                  mapTagNamesEnabled = true;
                  spanStartTimeShift = "1h";
                  spanEndTimeShift = "1h";
                };
                tracesToMetrics = {
                  datasourceUid = "VictoriaMetrics";
                  tags = [
                    {
                      key = "service.name";
                      value = "service";
                    }
                  ];
                  queries = [
                    {
                      name = "Error rate";
                      query = "sum by (client,server) (rate(traces_service_graph_request_failed_total{$$__tags}[$$__rate_interval]))";
                    }
                    {
                      name = "Latency rate";
                      query = "sum by (client,server) (rate(traces_spanmetrics_latency_bucket{$$__tags}[$$__rate_interval]))";
                    }
                    {
                      name = "Request rate";
                      query = "sum by (client,server) (rate(traces_service_graph_request_total{$$__tags}[$$__rate_interval]))";
                    }
                  ];
                };
              };
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
    #
    # Since caddy support native http dynamic SRV backend pools, we can also
    # utilize caddy to grafana to tempo datasource integration rather than
    # adding another dependency to routing machine as a potential central failure
    # point.
    services.caddy = {
      enable = true;
      configFile = let
        cfg = config.services.vmalert.datasources.loki;
      in
        pkgs.writeText "Caddyfile" ''
          # globals
          {
            debug
            log {
              level debug
              format json {
                time_format iso8601
              }
              include http.handlers.reverse_proxy
              include http.log.access.log0
              include http.log.access.log1
            }
          }

          # Reverse proxy for Loki vmalert
          http://:3099 {
            handle /prometheus/api/v1/rules {
              reverse_proxy http://${cfg.httpListenAddr} {
                rewrite /vmalert-loki/api/v1/rules
              }
            }

            handle {
              reverse_proxy http://127.0.0.1:3100 {
                transport http {
                  read_timeout 600s
                }
              }
            }
          }

          # Reverse proxy for SRV backend pools
          http://:3098 {
            # Utilize caddy for LB to Tempo SRV backends
            handle_path /tempo/* {
              reverse_proxy {
                dynamic srv {
                  name tempo.service.consul
                  refresh 10s
                  dial_timeout 1s
                  dial_fallback_delay -1s
                }
              }
            }

            # Utilize caddy for LB to Jaeger tracing SRV backends
            # TRACING_OPENTELEMETRY_JAEGER_ADDRESS = "http://127.0.0.1:3098/tempo-jaeger-thrift-http/";
            handle_path /tempo-jaeger-thrift-http/* {
              reverse_proxy {
                dynamic srv {
                  name tempo-jaeger-thrift-http.service.consul
                  refresh 10s
                  dial_timeout 1s
                  dial_fallback_delay -1s
                }
              }
            }
          }
        '';
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
        environmentFile = runKeyMaterial.alertmanager;
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
          {
            job_name = "vmagent";
            scrape_interval = "60s";
            metrics_path = "${config.services.vmagent.httpPathPrefix}/metrics";
            static_configs = [
              {
                targets = [config.services.vmagent.httpListenAddr];
                labels.alias = "vmagent";
              }
            ];
          }
        ]
        ++
        # Add a vmagent target scrape for each services.vmalert.datasources attr
        (builtins.attrValues (
          mapAttrs (name: cfgDs: {
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
        ))
        ++ optionals cfg.useTempo [
          {
            job_name = "tempo";
            scrape_interval = "60s";
            metrics_path = "/tempo/metrics";
            static_configs = [
              {
                # Utilize the monitoring caddy reverse proxy with dynamic SRV for tempo metrics
                targets = ["127.0.0.1:3098"];
                labels.alias = "tempo";
              }
            ];
          }
        ];
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
          externalAlertSource = ''explore?left=%%7B%%22datasource%%22:%%22VictoriaMetrics%%22,%%22queries%%22:%%5B%%7B%%22refId%%22:%%22A%%22,%%22expr%%22:%%22{{$expr|quotesEscape|pathEscape}}%%22,%%22range%%22:true,%%22editorMode%%22:%%22code%%22%%7D%%5D,%%22range%%22:%%7B%%22from%%22:%%22now-1h%%22,%%22to%%22:%%22now%%22%%7D%%7D&orgId=1'';
        };
        loki = {
          datasourceUrl = "http://127.0.0.1:3100/loki";
          httpListenAddr = "0.0.0.0:8881";
          externalUrl = "https://monitoring.${domain}";
          httpPathPrefix = "/vmalert-loki";
          externalAlertSource = ''explore?left=%%7B%%22datasource%%22:%%22Loki%%22,%%22queries%%22:%%5B%%7B%%22refId%%22:%%22A%%22,%%22expr%%22:%%22{{$expr|quotesEscape|pathEscape}}%%22,%%22range%%22:true,%%22editorMode%%22:%%22code%%22%%7D%%5D,%%22range%%22:%%7B%%22from%%22:%%22now-1h%%22,%%22to%%22:%%22now%%22%%7D%%7D&orgId=1'';
          # Loki uses PromQL type queries that do not strictly comply with PromQL
          # Ref: https://github.com/VictoriaMetrics/VictoriaMetrics/issues/780
          ruleValidateExpressions = false;
        };
      };
    };

    services.loki = {
      configuration = {
        auth_enabled = false;

        ingester = {
          chunk_idle_period = "5m";
          chunk_retain_period = "30s";
          lifecycler = {
            address = "127.0.0.1";
            final_sleep = "0s";
            ring = {
              kvstore = {store = "inmemory";};
              replication_factor = 1;
            };
          };
        };

        limits_config = {
          enforce_metric_name = false;
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
          ingestion_rate_mb = 160;
          ingestion_burst_size_mb = 160;
        };

        schema_config = {
          configs = [
            {
              from = "2020-05-15";
              index = {
                period = "168h";
                prefix = "index_";
              };
              object_store = "filesystem";
              schema = "v11";
              store = "boltdb";
            }
          ];
        };

        server.http_listen_port = 3100;

        storage_config = {
          boltdb = {directory = "/var/lib/loki/index";};
          filesystem = {directory = "/var/lib/loki/chunks";};
        };

        ruler = {
          enable_api = true;
          enable_alertmanager_v2 = true;
          ring.kvstore.store = "inmemory";
          rule_path = "/var/lib/loki/rules-temp";
          storage = {
            type = "local";
            local.directory = "/var/lib/loki/rules";
          };
        };
      };
    };

    systemd.services.victoriametrics-service =
      (pkgs.consulRegister {
        pkiFiles = {inherit caCertFile;};
        service = {
          name = "victoriametrics";
          port = 8428;

          checks = {
            victoriametrics-tcp = {
              interval = "10s";
              timeout = "5s";
              tcp = "127.0.0.1:8428";
            };
          };
        };
      })
      .systemdService;

    systemd.services.loki-service =
      (pkgs.consulRegister {
        pkiFiles = {inherit caCertFile;};
        service = {
          name = "loki";
          port = 3100;

          checks = {
            loki-tcp = {
              interval = "10s";
              timeout = "5s";
              tcp = "127.0.0.1:3100";
            };
          };
        };
      })
      .systemdService;

    secrets = mkIf isSops {
      generate.grafana-password = ''
        export PATH="${makeBinPath (with pkgs; [coreutils sops xkcdpass])}"

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
        target = runKeyMaterial.alertmanager;
        script = ''
          chmod 0600 ${runKeyMaterial.alertmanager}
          chown alertmanager:alertmanager ${runKeyMaterial.alertmanager}
        '';
        #  # File format for alertmanager secret file
        #  DEADMANSSNITCH="$SECRET_ENDPOINT"
        #  PAGERDUTY="$SECRET_KEY"
      };

      install.grafana-password.script = ''
        export PATH="${makeBinPath (with pkgs; [sops coreutils])}"

        mkdir -p /var/lib/grafana

        cat ${etcEncrypted}/grafana-password.json \
          | sops -d /dev/stdin \
          > /var/lib/grafana/password
      '';
    };

    age.secrets = mkIf (!isSops) {
      alertmanager = {
        file = config.age.encryptedRoot + "/monitoring/alertmanager.age";
        path = runKeyMaterial.alertmanager;
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
