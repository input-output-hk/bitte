{ config, pkgs, lib, ... }:
let
  cfg = config.services.victoriametrics;
  cfgVmagent = config.services.vmagent;
  cfgVmalert = config.services.vmalert;
in with lib; {
  disabledModules = [ "services/databases/victoriametrics.nix" ];
  options.services.victoriametrics = {
    enable = mkEnableOption "victoriametrics";
    enableVmalertProxy = mkEnableOption "vmalertProxy";
    package = mkOption {
      type = types.package;
      default = pkgs.victoriametrics;
      defaultText = "pkgs.victoriametrics";
      description = ''
        The VictoriaMetrics distribution to use.
      '';
    };
    httpListenAddr = mkOption {
      default = ":8428";
      type = types.str;
      description = ''
        The listen address for the http interface.
      '';
    };
    retentionPeriod = mkOption {
      type = types.int;
      default = 1;
      description = ''
        Retention period in months.
      '';
    };
    selfScrapeInterval = mkOption {
      default = "60s";
      type = types.str;
      description = ''
        The default time to self-scrape VictoriaMetrics' metrics.
        Set to "0" to disable.
      '';
    };
    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra options to pass to VictoriaMetrics. See the README: <link
        xlink:href="https://github.com/VictoriaMetrics/VictoriaMetrics/blob/master/README.md" />
        or <command>victoriametrics -help</command> for more
        information.
      '';
    };
  };

  options.services.vmagent = {
    enable = mkEnableOption "vmagent";
    package = mkOption {
      type = types.package;
      default = pkgs.victoriametrics;
      defaultText = "pkgs.victoriametrics";
      description = ''
        The VictoriaMetrics distribution to use for vmagent.
      '';
    };
    httpListenAddr = mkOption {
      default = "127.0.0.1:8429";
      type = types.str;
      description = ''
        Address to listen for http connections.
      '';
    };
    httpPathPrefix = mkOption {
      default = "";
      type = types.str;
      description = ''
        An optional prefix to add to all the paths handled by http server.
        For example, if '-http.pathPrefix=/foo/bar' is set,
        then all the http requests will be handled on '/foo/bar/*' paths.
        This may be useful for proxied requests.

        The httpPathPrefix should match the externalUrl path, if any.

        See:
          https://www.robustperception.io/using-external-urls-and-proxies-with-prometheus
      '';
    };
    promscrapeConfig = mkOption {
      default = [];
      type = types.listOf types.attrs;
      description = ''
        A list of attrs comprising scrape configurations.
        Each attr comprises a <scrape_config>.
        Vmalert supports Prometheus style scrape configuration format.

        Detailed syntax for scrape config can be found at:
          https://docs.victoriametrics.com/vmagent.html#how-to-collect-metrics-in-prometheus-format
          https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config

        While the document references above provide scrape config examples in yaml,
        this nix option expects a list of scrape config attrs to be convertable to JSON by:

          builtins.toJSON { scrape_configs = config.services.vmagent.promscrapeConfig; }
      '';
    };
    remoteWriteTmpDataPath = mkOption {
      default = "/tmp/vmagent-remotewrite-data";
      type = types.str;
      description = ''
        Path to directory where temporary data for remote write component is stored.
      '';
    };
    remoteWriteUrl = mkOption {
      default = "http://localhost:8428/api/v1/write";
      type = types.str;
      description = ''
        Remote storage URL to write data to. It must support Prometheus remote_write API.
        It is recommended using VictoriaMetrics as remote storage.
        Supports an array of values separated by comma.
      '';
    };
  };

  options.services.vmalert = let
  in {
    enable = mkEnableOption "vmalert";
    datasources = mkOption {
      default = {};
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          enable = mkEnableOption "vmalertType";
          name = lib.mkOption {
            type = types.str;
            default = name;
          };
          package = mkOption {
            type = types.package;
            default = pkgs.victoriametrics;
            defaultText = "pkgs.victoriametrics";
            description = ''
              The VictoriaMetrics distribution to use for vmalert.
            '';
          };
          datasourceUrl = mkOption {
            default = "http://localhost:8428";
            type = types.str;
            description = ''
              VictoriaMetrics or vmselect url.
              Required parameter.
            '';
          };
          externalAlertSource = mkOption {
            default = "";
            type = types.str;
            description = ''
              External Alert Source allows to override the Source link for alerts sent
              to AlertManager for cases where you want to build a custom link to Grafana,
              Prometheus or any other service.
              eg. 'explore?orgId=1&left=[\"now-1h\",\"now\",\"VictoriaMetrics\",{\"expr\": \"\"},{\"mode\":\"Metrics\"},{\"ui\":[true,true,true,\"none\"]}]'.
              If empty string, '/api/v1/:groupID/alertID/status' is used
            '';
          };
          externalUrl = mkOption {
            default = "http://localhost:8428";
            type = types.str;
            description = ''
              External URL is used as alert's source for sent alerts to the notifier.
            '';
          };
          httpListenAddr = mkOption {
            default = "127.0.0.1:8880";
            type = types.str;
            description = ''
              Address to listen for http connections.
            '';
          };
          httpPathPrefix = mkOption {
            default = "";
            type = types.str;
            description = ''
              An optional prefix to add to all the paths handled by http server.
              For example, if '-http.pathPrefix=/foo/bar' is set,
              then all the http requests will be handled on '/foo/bar/*' paths.
              This may be useful for proxied requests.

              The httpPathPrefix should match the externalUrl path, if any.

              See:
                https://www.robustperception.io/using-external-urls-and-proxies-with-prometheus
            '';
          };
          notifierUrl = mkOption {
            default = "http://localhost:9093/alertmanager";
            type = types.str;
            description = ''
              The URL for notifying prometheus alertmanager.
              Note that if the prometheus.alertmanager.webExternalUrl
              parameter contains a path, it will need to also be
              included here.
            '';
          };
          remoteReadUrl = mkOption {
            default = "http://localhost:8428";
            type = types.str;
            description = ''
              VM-single addr for restoring alerts state after restart.
            '';
          };
          remoteWriteUrl = mkOption {
            default = "http://localhost:8428";
            type = types.str;
            description = ''
              VM-single addr to persist alerts state and recording rules results.
            '';
          };
          ruleValidateExpressions = mkOption {
             type = types.bool;
             default = true;
             description = ''
               Whether to validate rules expressions via MetricsQL engine (default true).
               This option may be turned off to allow non-strict MetricsQL queries, such as for Loki.
               Ref: https://github.com/VictoriaMetrics/VictoriaMetrics/issues/780
             '';
          };
          rules = mkOption {
            default = {};
            type = types.attrs;
            description = ''
              An attribute set for declaring vmalert rules files.
              Each attribute name will be converted to a filename of: "''${attrName}-rules".
              Each attribute value will be comprised of a vmalert <rule_group>.
              Vmalert supports Prometheus alerting rules definition format.

              The attribute values representing a <rule_group> can be obtained from
              functionalized import which will allow nix interpolation if required.

              Examples of setting rules files follow:

                services.vmalert.datasources = {
                  vm.rules = { worldrepo-vm = import ../../cloud/alerts/worldrepo-vm.nix {}; };
                  loki.rules = { worldrepo-loki = import ../../cloud/alerts/worldrepo-loki.nix {}; };
                };

              All declared rules files for a specific datasource will be linkFarm joined
              into a single directory and provided to the vmalert service specifically
              configured to manage alerts for that datasource.

              Detailed syntax for rule groups can be found at:
                https://docs.victoriametrics.com/vmalert.html#groups
                https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/#defining-alerting-rules

              While the document references above provide rule group examples in yaml,
              this nix option expects the rules attribute set values to be convertable to JSON by:

                (builtins.toJSON config.services.vmalert.''${datasources}.rules)
            '';
          };
        };
      }));
    };
  };

  config = {
    systemd.services = {
      victoriametrics = mkIf cfg.enable {
        description = "VictoriaMetrics time series database";
        after = [ "network.target" ];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = 1;
          StartLimitBurst = 5;
          StateDirectory = "victoriametrics";
          DynamicUser = true;
          ExecStart = let
            cfgDs = cfgVmalert.datasources.vm;
            proxyUrl = "http://${cfgDs.httpListenAddr}${cfgDs.httpPathPrefix}";
          in ''
            ${cfg.package}/bin/victoria-metrics \
              -storageDataPath=/var/lib/victoriametrics \
              -httpListenAddr=${cfg.httpListenAddr} \
              -retentionPeriod=${toString cfg.retentionPeriod} \
              -selfScrapeInterval=${cfg.selfScrapeInterval} \
              ${if cfg.enableVmalertProxy && cfgVmalert.enable then "-vmalert.proxyURL=${proxyUrl} \\" else "\\"}
              ${escapeShellArgs cfg.extraOptions}
          '';
        };
        wantedBy = [ "multi-user.target" ];

        postStart = let
          bindAddr =
            (optionalString (hasPrefix ":" cfg.httpListenAddr) "127.0.0.1")
            + cfg.httpListenAddr;
        in mkBefore ''
          until ${
            getBin pkgs.curl
          }/bin/curl -s -o /dev/null http://${bindAddr}/ping; do
            sleep 1;
          done
        '';
      };

      vmagent = mkIf cfgVmagent.enable {
        description = "VictoriaMetrics vmagent";
        after = [ "network.target" ];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = 1;
          StartLimitBurst = 5;
          StateDirectory = "vmagent";
          DynamicUser = true;
          ExecStart = ''
            ${cfgVmagent.package}/bin/vmagent \
              -http.pathPrefix=${cfgVmagent.httpPathPrefix} \
              -httpListenAddr=${cfgVmagent.httpListenAddr} \
              -remoteWrite.tmpDataPath=${cfgVmagent.remoteWriteTmpDataPath} \
              -remoteWrite.url=${cfgVmagent.remoteWriteUrl} \
              -promscrape.config=${pkgs.writeText "vmagent-scrape-config.json" (builtins.toJSON { scrape_configs = cfgVmagent.promscrapeConfig; })}
          '';
        };
        wantedBy = [ "multi-user.target" ];
      };
    } // (optionalAttrs cfgVmalert.enable (mapAttrs' (name: cfgDs: nameValuePair "vmalert-${name}" {
      description = "VictoriaMetrics vmalert-${name}";
      after = [ "network.target" ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 1;
        StartLimitBurst = 5;
        StateDirectory = "vmalert-${name}";
        DynamicUser = true;
        ExecStart = let
          linkFarmDir = lib.pipe cfgDs.rules [
            (lib.mapAttrs (n: rulesNix: builtins.toJSON rulesNix))
            (lib.mapAttrs' (n: rulesJson:
              lib.nameValuePair
                "${n}-rules.json"
                (pkgs.writeText "${n}-rules.json" rulesJson
              )
            ))
            (lib.mapAttrsToList (name: path: { inherit name path; }))
            (pkgs.linkFarm "${name}-rules")
          ];
        in ''
          ${cfgDs.package}/bin/vmalert \
            -datasource.url=${cfgDs.datasourceUrl} \
            -external.alert.source=${cfgDs.externalAlertSource} \
            -external.url=${cfgDs.externalUrl} \
            -http.pathPrefix=${cfgDs.httpPathPrefix} \
            -httpListenAddr=${cfgDs.httpListenAddr} \
            -remoteRead.url=${cfgDs.remoteReadUrl} \
            -remoteWrite.url=${cfgDs.remoteWriteUrl} \
            -notifier.url=${cfgDs.notifierUrl} \
            -rule.validateExpressions=${boolToString cfgDs.ruleValidateExpressions} \
            -rule='${linkFarmDir}/*.json'
        '';
      };
      wantedBy = [ "multi-user.target" ];
    }) cfgVmalert.datasources));
  };
}
