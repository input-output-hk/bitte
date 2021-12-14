{ lib, config, pkgs, ... }:
let
  cfg = config.services.nomad-autoscaler;
  inherit (pkgs) sanitize;

  pluginModule = submodule ({ name, ... }: {
    options = {
      args = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = ''
          Specifies a set of arguments to pass to the plugin binary when it is
          executed.
        '';
      };

      driver = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          The plugin's executable name relative to to the plugin_dir. If the
          plugin has a suffix, such as .exe, this should be omitted.
        '';
      };

      config = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
        description = ''
          Specifies configuration values for the plugin either as HCL or JSON.
          The accepted values are plugin specific. Please refer to the
          individual plugin's documentation.
        '';
      };
    };
  });

  scalingModule = submodule ({ name, ... }: {
    options = {
      enabled = lib.mkEnableOption ''
        A boolean flag that allows operators to administratively disable a
        policy from active evaluation.
      '';

      min = lib.mkOption {
        type = with lib.types; ints.positive;
        description = ''
          The minimum running count of the targeted resource. This can be 0 or
          any positive integer.
        '';
      };

      max = lib.mkOption {
        type = with lib.types; ints.positive;
        description = ''
          The maximum running count of the targeted resource. This can be 0 or
          any positive integer.
        '';
      };

      policy = {
        cooldown = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = ''
            A time interval after a scaling action during which no additional
            scaling will be performed on the resource. It should be provided
            as a duration (e.g.: "5s", "1m"). If omitted the configuration
            value policy_default_cooldown from the agent will be used.
          '';
        };

        evaluation_interval = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = ''
            Defines how often the policy is evaluated by the Autoscaler. It
            should be provided as a duration (e.g.: "5s", "1m"). If omitted
            the configuration value default_evaluation_interval from the
            agent will be used.
          '';
        };

        target = lib.mkOption {
          # although there are more types, this is the only one we use.
          type = with lib.types; attrsOf targetAwsAsgModule;
          default = { };
          description = ''
            Defines where the autoscaling target is running. Detailed information on
            the configuration options can be found on the Target Plugins page.
          '';
        };

        check = lib.mkOption {
          type = with lib.types; attrsOf checkModule;
          default = { };
          description = ''
            Specifies one or more checks to be executed when determining if a scaling
            action is required.
          '';
        };
      };
    };
  });

  checkModule = submodule ({ name, ... }: {
    options = {
      source = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          The APM plugin that should handle the metric query. If
          omitted, this defaults to using the Nomad APM.
        '';
      };

      query = lib.mkOption {
        type = with lib.types; str;
        description = ''
          The query to run against the specified APM. Currently this
          query should return a single value. Detailed information on
          the configuration options can be found on the APM Plugins
          page.
        '';
      };

      query_window = lib.mkOption {
        type = with lib.types; str;
        default = "1m";
        description = ''
          Defines how far back to query the APM for metrics. It
          should be provided as a duration (e.g.: "5s", "1m").
        '';
      };

      strategy = lib.mkOption {
        type = with lib.types; attrsOf checkStrategyModule;
        default = { };
        description = ''
          The strategy to use, and it's configuration when
          calculating the desired state based on the current count
          and the metric returned by the APM. Detailed information on
          the configuration options can be found on the Strategy
          Plugins page.
        '';
      };
    };
  });

  checkStrategyModule = submodule ({ name, ... }: {
    options = {
      target = lib.mkOption { type = with lib.types; float; };

      threshold = lib.mkOption {
        type = with lib.types; float;
        default = 1.0e-2;
      };
    };
  });

  targetAwsAsgModule = submodule ({ name, ... }: {
    options = {
      dry-run = lib.mkEnableOption "Whether to deploy in dry-run mode";

      aws_asg_name = lib.mkOption {
        type = with lib.types; str;
        description = ''
          The name of the AWS AutoScaling Group to interact with when performing
          scaling actions.
        '';
      };

      node_class = lib.mkOption {
        type = with lib.types; str;
        description = ''
          The Nomad client node class identifier used to group nodes into a pool
          of resource.
        '';
      };

      node_drain_deadline = lib.mkOption {
        type = with lib.types; str;
        default = "15m";
        description = ''
          The Nomad drain deadline to use when performing node draining actions.
          Please note that the default value for this setting differs from
          Nomad's default of 1h.
        '';
      };

      node_drain_ignore_system_jobs = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description = ''
          A boolean flag used to control if system jobs should be stopped when
          performing node draining actions.
        '';
      };

      node_purge = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description = ''
          A boolean flag to determine whether Nomad clients should be purged when
          performing scale in actions.
        '';
      };

      node_selector_strategy = lib.mkOption {
        type = with lib.types; str;
        default = "least_busy";
        description = ''
          The strategy to use when selecting nodes for termination. Please see
          the node selector strategy documentation for more detailed information.
        '';
      };
    };
  });

in {
  options.services.nomad-autoscaler = {
    enable = lib.mkEnableOption "nomad-autoscaler";

    package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.nomad-autoscaler;
      description = "The nomad-autoscaler package to use.";
    };

    log_level = lib.mkOption {
      type = with lib.types; enum [ "DEBUG" "INFO" "WARN" "TRACE" ];
      default = "INFO";
      description = ''
        Specify the verbosity level of Nomad Autoscaler's logs.
        Valid values include DEBUG, INFO, and WARN, in decreasing order of verbosity.
      '';
    };

    log_json = lib.mkEnableOption "Output logs in a JSON format";

    plugin_dir = lib.mkOption {
      type = with lib.types; path;
      default = "${cfg.package}/share";
      description = ''
        The plugin directory is used to discover Nomad Autoscaler plugins.
      '';
    };

    http = {
      bind_address = lib.mkOption {
        type = with lib.types; str;
        default = "127.0.0.1";
        description = "The HTTP address that the server will bind to.";
      };

      bind_port = lib.mkOption {
        type = with lib.types; port;
        default = 8080;
        description = "The port that the server will bind to.";
      };
    };

    nomad = {
      address = lib.mkOption {
        type = with lib.types; str;
        default = "http://127.0.0.1:4646";
        description =
          "The address of the Nomad server in the form of protocol://addr:port.";
      };

      region = lib.mkOption {
        type = with lib.types; str;
        default = "global";
        description = "The region of the Nomad servers to connect with.";
      };

      namespace = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "The target namespace for queries and actions bound to a namespace.";
      };

      token = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "The SecretID of an ACL token to use to authenticate API requests with.";
      };

      http_auth = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "The authentication information to use when connecting to a Nomad API which is using HTTP authentication.";
      };

      ca_cert = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Path to a PEM encoded CA cert file to use to verify the Nomad server SSL certificate.";
      };

      ca_path = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Path to a directory of PEM encoded CA cert files to verify the Nomad server SSL certificate.";
      };

      client_cert = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Path to a PEM encoded client certificate for TLS authentication to the Nomad server.";
      };

      client_key = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Path to an unencrypted PEM encoded private key matching the client certificate.";
      };

      tls_server_name = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "The server name to use as the SNI host when connecting via TLS.";
      };

      skip_verify = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description =
          "Do not verify TLS certificates. This is strongly discouraged. ";
      };
    };

    policy = {
      dir = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = "The path to a directory used to load scaling policies.";
      };

      default_cooldown = lib.mkOption {
        type = with lib.types; str;
        default = "5m";
        description =
          "The default cooldown that will be applied to all scaling policies which do not specify a cooldown period.";
      };

      default_evaluation_interval = lib.mkOption {
        type = with lib.types; str;
        default = "10s";
        description =
          "The default evaluation interval that will be applied to all scaling policies which do not specify an evaluation interval.";
      };
    };

    policy_eval = {
      ack_timeout = lib.mkOption {
        type = with lib.types; str;
        default = "5m";
        description =
          "The time limit that an eval must be ACK'd before being considered N";
      };

      delivery_limit = lib.mkOption {
        type = with lib.types; int;
        default = 1;
        description =
          "The maximum number of times a policy evaluation can be dequeued from the b";
      };

      workers = lib.mkOption {
        type = with lib.types; attrsOf int;
        default = {
          cluster = 10;
          horizontal = 10;
        };
        description =
          "The number of workers to initialize for each queue. Nomad Autoscaler supports cluster and horizontal map keys. Nomad Autoscaler Enterprise supports additional vertical_mem and vertical_cpu entries.";
      };
    };

    telemetry = {
      disable_hostname = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description =
          "Specifies if gauge values should be prefixed with the local hostname.";
      };

      enable_hostname_label = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description = "Enable adding hostname to metric labels.";
      };

      collection_interval = lib.mkOption {
        type = with lib.types; str;
        default = "1s";
        description =
          "Specifies the time interval at which the Nomad agent collects telemetry data.";
      };

      statsite_address = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies the address of a statsite server to forward metrics data to.";
      };

      statsd_address = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies the address of a statsd server to forward metrics to.";
      };

      dogstatsd_address = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies the address of a DataDog statsd server to forward metrics to.";
      };

      dogstatsd_tags = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description =
          "Specifies a list of global tags that will be added to all telemetry packets sent to DogStatsD. It is a list of strings, where each string looks like my_tag_name:my_tag_value.";
      };

      prometheus_metrics = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description =
          "Specifies whether the agent should make Prometheus formatted metrics available at /v1/metrics?format=prometheus.";
      };

      prometheus_retention_time = lib.mkOption {
        type = with lib.types; str;
        default = "24h";
        description =
          "Specifies the amount of time that Prometheus metrics are retained in memory.";
      };

      circonus_api_token = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies a valid Circonus API Token used to create/manage check. If provided, metric management is enabled.";
      };

      circonus_api_app = lib.mkOption {
        type = with lib.types; str;
        default = "nomad-autoscaler";
        description =
          "Specifies a valid app name associated with the API token.";
      };

      circonus_api_url = lib.mkOption {
        type = with lib.types; str;
        default = "https://api.circonus.com/v2";
        description =
          "Specifies the base URL to use for contacting the Circonus API.";
      };

      circonus_submission_interval = lib.mkOption {
        type = with lib.types; str;
        default = "10s";
        description =
          "Specifies the interval at which metrics are submitted to Circonus.";
      };

      circonus_submission_url = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies the check.config.submission_url field, of a Check API object, from a previously created HTTPTRAP check.";
      };

      circonus_check_id = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies the Check ID (not check bundle) from a previously created HTTPTrap check. The numeric portion of the check._cid field in the Check API object.";
      };

      circonus_check_force_metric_activation = lib.mkOption {
        type = with lib.types; bool;
        default = false;
        description =
          "SEcifies if force activation of metrics which already exist and are not currently active. If check management is enabled, the default behavior is to add new metrics as they are encountered. If the metric already exists in the check, it will not be activated. This setting overrides that behavior.";
      };

      circonus_check_instance_id = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description = ''
          Serves to uniquely identify the metrics coming from this instance. It can be used to maintain metric continuity with transient or ephemeral instances as they move around within an infrastructure. By default, this is set to " hostname:application name " (e.g. host123:nomad-autoscaler).'';
      };

      circonus_check_search_tag = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies a special tag which, when coupled with the instance id, helps to narrow down the search results when neither a Submission URL or Check ID is provided. By default, this is set to "
          "service:app" " (e.g. service:nomad-autoscaler).";
      };

      circonus_check_display_name = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies a name to give a check when it is created. This name is displayed in the Circonus UI Checks list.";
      };

      circonus_check_tags = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Comma separated list of additional tags to add to a check when it is created.";
      };

      circonus_broker_id = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies the ID of a specific Circonus Broker to use when creating a new check. The numeric portion of broker._cid field in a Broker API object. If metric management is enabled and neither a Submission URL nor Check ID is provided, an attempt will be made to search for an existing check using Instance ID and Search Tag. If one is not found, a new HTTPTrap check will be created. By default, this is a random Enterprise Broker is selected, or, the default Circonus Public Broker.";
      };

      circonus_broker_select_tag = lib.mkOption {
        type = with lib.types; str;
        default = "";
        description =
          "Specifies a special tag which will be used to select a Circonus Broker when a Broker ID is not provided. The best use of this is to as a hint for which broker should be used based on where this particular instance is running (e.g., a specific geographic location or datacenter, dc:sfo).";
      };
    };

    apm = lib.mkOption {
      default = { };
      type = with lib.types; attrsOf pluginModule;
      description =
        "The apm block is used to configure application performance metric (APM) plugins.";
    };

    target = lib.mkOption {
      default = { };
      type = with lib.types; attrsOf pluginModule;
      description =
        "The target block is used to configure scaling target plugins.";
    };

    strategy = lib.mkOption {
      default = { };
      type = with lib.types; attrsOf pluginModule;
      description =
        "The strategy block is used to configure scaling strategy plugins.";
    };

    policies = lib.mkOption {
      default = { };
      type = with lib.types; attrsOf scalingModule;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = {
      "nomad-autoscaler.d/config.json".source = pkgs.toPrettyJSON "config"
        (sanitize {
          inherit (cfg)
            plugin_dir log_json log_level http nomad policy policy_eval
            telemetry apm target strategy;
        });
      "nomad-autoscaler.d/policies/policies.json".source =
        pkgs.toPrettyJSON "policies.json" { scaling = sanitize cfg.policies; };
    };

    systemd.services.nomad-autoscaler = {
      description = "Nomad Autoscaler Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      restartTriggers = [
        config.environment.etc."nomad-autoscaler.d/config.json".source
        config.environment.etc."nomad-autoscaler.d/policies/policies.json".source
      ];

      # restarting causes issues for now:
      # https://github.com/hashicorp/nomad-autoscaler/issues/410#issuecomment-789237902
      restartIfChanged = false;
      reloadIfChanged = true;

      unitConfig = {
        StartLimitInterval = "20s";
        StartLimitBurst = 10;
      };

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
          unset AWS_DEFAULT_REGION

          set -x
          ${cfg.package}/bin/nomad-autoscaler agent -config /etc/nomad-autoscaler.d/config.json
        '';

        # support reloading: HUP tells autoscaler to reload config files
        ExecReload = [ "${pkgs.coreutils}/bin/kill -HUP $MAINPID" ];
        Restart = "on-failure";
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
