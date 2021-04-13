{ lib, config, pkgs, ... }:
let cfg = config.services.nomad-autoscaler;
  inherit (lib) mkOption mkEnableOption types mkIf;
  inherit (types) enum path package attrsOf submodule port str bool int listOf;
  inherit (pkgs) sanitize;
in
{
  options.services.nomad-autoscaler = {
    enable = mkEnableOption "nomad-autoscaler";

    package = mkOption {
      type = package;
      default = pkgs.nomad-autoscaler;
      description = "The nomad-autoscaler package to use.";
    };

    logLevel = mkOption {
      type = enum [ "DEBUG" "INFO" "WARN" ];
      default = "INFO";
      description = ''
        Specify the verbosity level of Nomad Autoscaler's logs.
        Valid values include DEBUG, INFO, and WARN, in decreasing order of verbosity.
      '';
    };

    logJson = mkEnableOption "Output logs in a JSON format";

    pluginDir = mkOption {
      type = path;
      default = "${cfg.package.src}/plugins";
      description = ''
        The plugin directory is used to discover Nomad Autoscaler plugins.
      '';
    };

    http = {
      bindAddress = mkOption {
        type = str;
        default = "127.0.0.1";
        description = "The HTTP address that the server will bind to.";
      };
      bindPort = mkOption {
        type = port;
        default = 8080;
        description = "The port that the server will bind to.";
      };
    };

    nomad = {
      address = mkOption {
        type = str;
        default = "http://127.0.0.1:4646";
        description = "The address of the Nomad server in the form of protocol://addr:port.";
      };

      region = mkOption {
        type = str;
        default = "global";
        description = "The region of the Nomad servers to connect with.";
      };

      namespace = mkOption {
        type = str;
        default = "";
        description = "The target namespace for queries and actions bound to a namespace.";
      };

      token = mkOption {
        type = str;
        default = "";
        description =
          "The SecretID of an ACL token to use to authenticate API requests with.";
      };

      httpAuth = mkOption {
        type = str;
        default = "";
        description =
          "The authentication information to use when connecting to a Nomad API which is using HTTP authentication.";
      };

      caCert = mkOption {
        type = str;
        default = "";
        description =
          "Path to a PEM encoded CA cert file to use to verify the Nomad server SSL certificate.";
      };

      caPath = mkOption {
        type = str;
        default = "";
        description =
          "Path to a directory of PEM encoded CA cert files to verify the Nomad server SSL certificate.";
      };

      clientCert = mkOption {
        type = str;
        default = "";
        description =
          "Path to a PEM encoded client certificate for TLS authentication to the Nomad server.";
      };

      clientKey = mkOption {
        type = str;
        default = "";
        description =
          "Path to an unencrypted PEM encoded private key matching the client certificate.";
      };

      tlsServerName = mkOption {
        type = str;
        default = "";
        description =
          "The server name to use as the SNI host when connecting via TLS.";
      };

      skipVerify = mkOption {
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
        description =
          "The path to a directory used to load scaling policies.";
      };
      defaultCooldown = mkOption {
        type = str;
        default = "5m";
        description =
          "The default cooldown that will be applied to all scaling policies which do not specify a cooldown period.";
      };
      defaultEvaluationInterval = mkOption {
        type = str;
        default = "10s";
        description =
          "The default evaluation interval that will be applied to all scaling policies which do not specify an evaluation interval.";
      };
    };

    policyEval = {
      ackTimeout = mkOption {
        type = str;
        default = "5m";
        description =
          "The time limit that an eval must be ACK'd before being considered N";
      };
      deliveryLimit = mkOption {
        type = int;
        default = 1;
        description =
          "The maximum number of times a policy evaluation can be dequeued from the b";
      };
      workers = mkOption {
        type = attrsOf int;
        default = { cluster = 10; horizontal = 10; };
        description =
          "The number of workers to initialize for each queue. Nomad Autoscaler supports cluster and horizontal map keys. Nomad Autoscaler Enterprise supports additional vertical_mem and vertical_cpu entries.";
      };
    };

    telemetry = {
      disableHostname = mkOption {
        type = bool;
        default = false;
        description =
          "Specifies if gauge values should be prefixed with the local hostname.";
      };
      enableHostnameLabel = mkOption {
        type = bool;
        default = false;
        description =
          "Enable adding hostname to metric labels.";
      };
      collectionInterval = mkOption {
        type = str;
        default = "1s";
        description =
          "Specifies the time interval at which the Nomad agent collects telemetry data.";
      };
      statsiteAddress = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the address of a statsite server to forward metrics data to.";
      };
      statsdAddress = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the address of a statsd server to forward metrics to.";
      };
      dogstatsdAddress = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the address of a DataDog statsd server to forward metrics to.";
      };
      dogstatsdTags = mkOption {
        type = listOf str;
        default = [ ];
        description =
          "Specifies a list of global tags that will be added to all telemetry packets sent to DogStatsD. It is a list of strings, where each string looks like my_tag_name:my_tag_value.";
      };
      prometheusMetrics = mkOption {
        type = bool;
        default = false;
        description =
          "Specifies whether the agent should make Prometheus formatted metrics available at /v1/metrics?format=prometheus.";
      };
      prometheusRetentionTime = mkOption {
        type = str;
        default = "24h";
        description =
          "Specifies the amount of time that Prometheus metrics are retained in memory.";
      };
      circonusApiToken = mkOption {
        type = str;
        default = "";
        description =
          "Specifies a valid Circonus API Token used to create/manage check. If provided, metric management is enabled.";
      };
      circonusApiApp = mkOption {
        type = str;
        default = "nomad-autoscaler";
        description =
          "Specifies a valid app name associated with the API token.";
      };
      circonusApiUrl = mkOption {
        type = str;
        default = "https://api.circonus.com/v2";
        description =
          "Specifies the base URL to use for contacting the Circonus API.";
      };
      circonusSubmissionInterval = mkOption {
        type = str;
        default = "10s";
        description =
          "Specifies the interval at which metrics are submitted to Circonus.";
      };
      circonusSubmissionUrl = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the check.config.submission_url field, of a Check API object, from a previously created HTTPTRAP check.";
      };
      circonusCheckId = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the Check ID (not check bundle) from a previously created HTTPTrap check. The numeric portion of the check._cid field in the Check API object.";
      };
      circonusCheckForceMetricActivation = mkOption {
        type = bool;
        default = false;
        description =
          "SEcifies if force activation of metrics which already exist and are not currently active. If check management is enabled, the default behavior is to add new metrics as they are encountered. If the metric already exists in the check, it will not be activated. This setting overrides that behavior.";
      };
      circonusCheckInstanceId = mkOption {
        type = str;
        default = "";
        description =
          ''Serves to uniquely identify the metrics coming from this instance. It can be used to maintain metric continuity with transient or ephemeral instances as they move around within an infrastructure. By default, this is set to " hostname:application name " (e.g. host123:nomad-autoscaler).'';
      };
      circonusCheckSearchTag = mkOption {
        type = str;
        default = "";
        description =
          "Specifies a special tag which, when coupled with the instance id, helps to narrow down the search results when neither a Submission URL or Check ID is provided. By default, this is set to " service:app " (e.g. service:nomad-autoscaler).";
      };
      circonusCheckDisplayName = mkOption {
        type = str;
        default = "";
        description =
          "Specifies a name to give a check when it is created. This name is displayed in the Circonus UI Checks list.";
      };
      circonusCheckTags = mkOption {
        type = str;
        default = "";
        description =
          "Comma separated list of additional tags to add to a check when it is created.";
      };
      circonusBrokerId = mkOption {
        type = str;
        default = "";
        description =
          "Specifies the ID of a specific Circonus Broker to use when creating a new check. The numeric portion of broker._cid field in a Broker API object. If metric management is enabled and neither a Submission URL nor Check ID is provided, an attempt will be made to search for an existing check using Instance ID and Search Tag. If one is not found, a new HTTPTrap check will be created. By default, this is a random Enterprise Broker is selected, or, the default Circonus Public Broker.";
      };
      circonusBrokerSelectTag = mkOption {
        type = str;
        default = "";
        description =
          "Specifies a special tag which will be used to select a Circonus Broker when a Broker ID is not provided. The best use of this is to as a hint for which broker should be used based on where this particular instance is running (e.g., a specific geographic location or datacenter, dc:sfo).";
      };
    };
  };

  config = mkIf
    cfg.enable
    {
      environment.etc."nomad-autoscaler.d/config.json".source =
        pkgs.toPrettyJSON "config" (sanitize {
          inherit (cfg) pluginDir logJson logLevel http nomad policy
            policyEval telemetry;
        });

      systemd.services.nomad-autoscaler = {
        description = "Nomad Autoscaler Service";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          StateDirectory = "nomad-autoscaler";
          RuntimeDirectory = "nomad-autoscaler";
          DynamicUser = true;
          User = "nomad-autoscaler";
          Group = "nomad-autoscaler";
          ExecStart =
            "${cfg.package}/bin/nomad-autoscaler agent -config /etc/nomad-autoscaler.d/config.json";
          # support reloading
          ExecReload = [
          ];
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
          SystemCallFilter =
            "~@cpu-emulation @keyring @module @obsolete @raw-io @reboot @swap @sync";
        };

      };
    };
}
