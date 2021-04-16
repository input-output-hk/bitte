{ lib, config, pkgs, ... }:
let
  cfg = config.services.nomad-autoscaler;
  inherit (lib) mkOption mkEnableOption types mkIf;
  inherit (types) enum path package attrsOf submodule port str bool int listOf;
  inherit (pkgs) sanitize;

  pluginModule = submodule ({ name, ... }: {
    options = {
      args = mkOption {
        type = listOf str;
        default = [ ];
        description =
          "Specifies a set of arguments to pass to the plugin binary when it is executed.";
      };

      driver = mkOption {
        type = str;
        default = "";
        description =
          "The plugin's executable name relative to to the plugin_dir. If the plugin has a suffix, such as .exe, this should be omitted.";
      };

      config = mkOption {
        type = attrsOf str;
        default = { };
        description =
          "Specifies configuration values for the plugin either as HCL or JSON. The accepted values are plugin specific. Please refer to the individual plugin's documentation.";
      };
    };
  });
in {
  options.services.nomad-autoscaler = {
    enable = mkEnableOption "nomad-autoscaler";

    package = mkOption {
      type = package;
      default = pkgs.nomad-autoscaler;
      description = "The nomad-autoscaler package to use.";
    };

    log_level = mkOption {
      type = enum [ "DEBUG" "INFO" "WARN" ];
      default = "INFO";
      description = ''
        Specify the verbosity level of Nomad Autoscaler's logs.
        Valid values include DEBUG, INFO, and WARN, in decreasing order of verbosity.
      '';
    };

    log_json = mkEnableOption "Output logs in a JSON format";

    plugin_dir = mkOption {
      type = path;
      default = "${cfg.package}/share";
      description = ''
        The plugin directory is used to discover Nomad Autoscaler plugins.
      '';
    };

    http = {
      bind_address = mkOption {
        type = str;
        default = "127.0.0.1";
        description = "The HTTP address that the server will bind to.";
      };

      bind_port = mkOption {
        type = port;
        default = 8080;
        description = "The port that the server will bind to.";
      };
    };

    nomad = {
      address = mkOption {
        type = str;
        default = "http://127.0.0.1:4646";
        description =
          "The address of the Nomad server in the form of protocol://addr:port.";
      };

      region = mkOption {
        type = str;
        default = "global";
        description = "The region of the Nomad servers to connect with.";
      };

      namespace = mkOption {
        type = str;
        default = "";
        description =
          "The target namespace for queries and actions bound to a namespace.";
      };

      token = mkOption {
        type = str;
        default = "";
        description =
          "The SecretID of an ACL token to use to authenticate API requests with.";
      };

      http_auth = mkOption {
        type = str;
        default = "";
        description =
          "The authentication information to use when connecting to a Nomad API which is using HTTP authentication.";
      };

      ca_cert = mkOption {
        type = str;
        default = "";
        description =
          "Path to a PEM encoded CA cert file to use to verify the Nomad server SSL certificate.";
      };

      ca_path = mkOption {
        type = str;
        default = "";
        description =
          "Path to a directory of PEM encoded CA cert files to verify the Nomad server SSL certificate.";
      };

      client_cert = mkOption {
        type = str;
        default = "";
        description =
          "Path to a PEM encoded client certificate for TLS authentication to the Nomad server.";
      };

      client_key = mkOption {
        type = str;
        default = "";
        description =
          "Path to an unencrypted PEM encoded private key matching the client certificate.";
      };

      tls_server_name = mkOption {
        type = str;
        default = "";
        description =
          "The server name to use as the SNI host when connecting via TLS.";
      };

      skip_verify = mkOption {
        type = bool;
        default = false;
        description =
          "Do not verify TLS certificates. This is strongly discouraged. ";
      };
    };

    policy = {
      dir = mkOption {
        type = str;
        default = "";
        description = "The path to a directory used to load scaling policies.";
      };

      default_cooldown = mkOption {
        type = str;
        default = "5m";
        description =
          "The default cooldown that will be applied to all scaling policies which do not specify a cooldown period.";
      };

      default_evaluation_interval = mkOption {
        type = str;
        default = "10s";
        description =
          "The default evaluation interval that will be applied to all scaling policies which do not specify an evaluation interval.";
      };
    };

    policy_eval = {
      ack_timeout = mkOption {
        type = str;
        default = "5m";
        description =
          "The time limit that an eval must be ACK'd before being considered N";
      };

      delivery_limit = mkOption {
        type = int;
        default = 1;
        description =
          "The maximum number of times a policy evaluation can be dequeued from the b";
      };

      workers = mkOption {
        type = attrsOf int;
        default = {
          cluster = 10;
          horizontal = 10;
        };
        description =
          "The number of workers to initialize for each queue. Nomad Autoscaler supports cluster and horizontal map keys. Nomad Autoscaler Enterprise supports additional vertical_mem and vertical_cpu entries.";
      };
    };

    telemetry = {
      disable_hostname = mkOption {
        type = bool;
        default = false;
        description =
          "Specifies if gauge values should be prefixed with the local hostname.";
      };

      enable_hostname_label = mkOption {
        type = bool;
        default = false;
        description = "Enable adding hostname to metric labels.";
      };

      collection_interval = mkOption {
        type = str;
        default = "1s";
        description =
          "Specifies the time interval at which the Nomad agent collects telemetry data.";
      };

      statsite_address = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the address of a statsite server to forward metrics data to.";
      };

      statsd_address = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the address of a statsd server to forward metrics to.";
      };

      dogstatsd_address = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the address of a DataDog statsd server to forward metrics to.";
      };

      dogstatsd_tags = mkOption {
        type = listOf str;
        default = [ ];
        description =
          "Specifies a list of global tags that will be added to all telemetry packets sent to DogStatsD. It is a list of strings, where each string looks like my_tag_name:my_tag_value.";
      };

      prometheus_metrics = mkOption {
        type = bool;
        default = false;
        description =
          "Specifies whether the agent should make Prometheus formatted metrics available at /v1/metrics?format=prometheus.";
      };

      prometheus_retention_time = mkOption {
        type = str;
        default = "24h";
        description =
          "Specifies the amount of time that Prometheus metrics are retained in memory.";
      };

      circonus_api_token = mkOption {
        type = str;
        default = "";
        description =
          "Specifies a valid Circonus API Token used to create/manage check. If provided, metric management is enabled.";
      };

      circonus_api_app = mkOption {
        type = str;
        default = "nomad-autoscaler";
        description =
          "Specifies a valid app name associated with the API token.";
      };

      circonus_api_url = mkOption {
        type = str;
        default = "https://api.circonus.com/v2";
        description =
          "Specifies the base URL to use for contacting the Circonus API.";
      };

      circonus_submission_interval = mkOption {
        type = str;
        default = "10s";
        description =
          "Specifies the interval at which metrics are submitted to Circonus.";
      };

      circonus_submission_url = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the check.config.submission_url field, of a Check API object, from a previously created HTTPTRAP check.";
      };

      circonus_check_id = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the Check ID (not check bundle) from a previously created HTTPTrap check. The numeric portion of the check._cid field in the Check API object.";
      };

      circonus_check_force_metric_activation = mkOption {
        type = bool;
        default = false;
        description =
          "SEcifies if force activation of metrics which already exist and are not currently active. If check management is enabled, the default behavior is to add new metrics as they are encountered. If the metric already exists in the check, it will not be activated. This setting overrides that behavior.";
      };

      circonus_check_instance_id = mkOption {
        type = str;
        default = "";
        description = ''
          Serves to uniquely identify the metrics coming from this instance. It can be used to maintain metric continuity with transient or ephemeral instances as they move around within an infrastructure. By default, this is set to " hostname:application name " (e.g. host123:nomad-autoscaler).'';
      };

      circonus_check_search_tag = mkOption {
        type = str;
        default = "";
        description =
          "Specifies a special tag which, when coupled with the instance id, helps to narrow down the search results when neither a Submission URL or Check ID is provided. By default, this is set to "
          "service:app" " (e.g. service:nomad-autoscaler).";
      };

      circonus_check_display_name = mkOption {
        type = str;
        default = "";
        description =
          "Specifies a name to give a check when it is created. This name is displayed in the Circonus UI Checks list.";
      };

      circonus_check_tags = mkOption {
        type = str;
        default = "";
        description =
          "Comma separated list of additional tags to add to a check when it is created.";
      };

      circonus_broker_id = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the ID of a specific Circonus Broker to use when creating a new check. The numeric portion of broker._cid field in a Broker API object. If metric management is enabled and neither a Submission URL nor Check ID is provided, an attempt will be made to search for an existing check using Instance ID and Search Tag. If one is not found, a new HTTPTrap check will be created. By default, this is a random Enterprise Broker is selected, or, the default Circonus Public Broker.";
      };

      circonus_broker_select_tag = mkOption {
        type = str;
        default = "";
        description =
          "Specifies a special tag which will be used to select a Circonus Broker when a Broker ID is not provided. The best use of this is to as a hint for which broker should be used based on where this particular instance is running (e.g., a specific geographic location or datacenter, dc:sfo).";
      };
    };

    apm = mkOption {
      default = { };
      type = attrsOf pluginModule;
      description =
        "The apm block is used to configure application performance metric (APM) plugins.";
    };

    target = mkOption {
      default = { };
      type = attrsOf pluginModule;
      description =
        "The target block is used to configure scaling target plugins.";
    };

    strategy = mkOption {
      default = { };
      type = attrsOf pluginModule;
      description =
        "The strategy block is used to configure scaling strategy plugins.";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."nomad-autoscaler.d/config.json".source =
      pkgs.toPrettyJSON "config" (sanitize {
        inherit (cfg)
          plugin_dir log_json log_level http nomad policy policy_eval telemetry
          apm target strategy;
      });

    systemd.services.nomad-autoscaler = {
      description = "Nomad Autoscaler Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      restartTriggers =
        [ config.environment.etc."nomad-autoscaler.d/config.json".source ];

      serviceConfig = {
        StateDirectory = "nomad-autoscaler";
        RuntimeDirectory = "nomad-autoscaler";

        # DynamicUser = true;
        # User = "nomad-autoscaler";
        # Group = "nomad-autoscaler";

        ExecStartPre = pkgs.writeBashChecked "nomad-autoscaler-pre" ''
          set -exuo pipefail
          cp /run/keys/nomad-autoscaler-token .
        '';

        ExecStart = pkgs.writeBashChecked "nomad-autsocaler" ''
          set -euo pipefail

          NOMAD_TOKEN="$(< nomad-autoscaler-token)"
          export NOMAD_TOKEN

          set -x
          ${cfg.package}/bin/nomad-autoscaler agent -config /etc/nomad-autoscaler.d/config.json
        '';

        # support reloading
        ExecReload = [ ];
        Restart = "on-failure";
        StartLimitInterval = "20s";
        StartLimitBurst = 10;
        TimeoutStopSec = "30s";
        RestartSec = "5s";
        # upstream hardening options
        NoNewPrivileges = true;
        ProtectHome = true;
        # ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
      };
    };
  };
}
