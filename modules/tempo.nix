{
  config,
  lib,
  pkgs,
  runKeyMaterial,
  pkiFiles,
  ...
}: let
  inherit
    (lib)
    flip
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    optionals
    pipe
    recursiveUpdate
    ;

  inherit
    (lib.types)
    attrs
    bool
    enum
    ints
    listOf
    nullOr
    port
    str
    ;

  inherit (pkiFiles) caCertFile;

  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  isSops = deployType == "aws";

  cfg = config.services.tempo;

  settingsFormat = pkgs.formats.yaml {};
in {
  options.services.tempo = {
    enable = mkEnableOption "Grafana Tempo";

    registerConsulService = mkOption {
      type = bool;
      default = true;
      description = ''
        Register a consul service for each Tempo protocol listener.
        The service naming will be of the form "tempo-$RECEIVER_TYPE".
      '';
    };

    memcachedEnable = mkOption {
      type = bool;
      default = true;
      description = ''
        Use memcached to improve performance of Tempo trace lookups.
        Redis support as a Tempo cache is still marked experimental.
      '';
    };

    memcachedMaxMb = mkOption {
      type = ints.positive;
      default = 1024;
      description = ''
        If memcached is enabled, use a default maximum of 1 GB RAM.
      '';
    };

    httpListenAddress = mkOption {
      type = str;
      default = "0.0.0.0";
      description = "HTTP server listen host.";
    };

    httpListenPort = mkOption {
      type = port;
      default = 3200;
      description = "HTTP server listen port.";
    };

    grpcListenPort = mkOption {
      type = port;
      default = 9096;
      description = "gRPC server listen port.";
    };

    receiverOtlpHttp = mkOption {
      type = bool;
      default = true;
      description = "Enable OTLP receiver on HTTP.";
    };

    receiverOtlpGrpc = mkOption {
      type = bool;
      default = true;
      description = "Enable OTLP receiver on gRPC.";
    };

    receiverJaegerThriftHttp = mkOption {
      type = bool;
      default = true;
      description = "Enable Jaeger thrift receiver on HTTP.";
    };

    receiverJaegerGrpc = mkOption {
      type = bool;
      default = true;
      description = "Enable Jaeger receiver on gRPC.";
    };

    receiverJaegerThriftBinary = mkOption {
      type = bool;
      default = true;
      description = "Enable Jaeger thrift receiver for binary.";
    };

    receiverJaegerThriftCompact = mkOption {
      type = bool;
      default = true;
      description = "Enable Jaeger thrift receiver on compact.";
    };

    receiverZipkin = mkOption {
      type = bool;
      default = true;
      description = "Enable Zipkin receiver.";
    };

    receiverOpencensus = mkOption {
      type = bool;
      default = true;
      description = "Enable Opencensus receiver.";
    };

    receiverKafka = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable Kafta receiver.
        Note: The Tempo service will fail if Tempo cannot reach a Kafka broker.

        See the following refs for configuration details:
        https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/kafkareceiver
        https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/kafkametricsreceiver
      '';
    };

    logReceivedSpansEnable = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable to log every received span to help debug ingestion
        or calculate span error distributions using the logs.
      '';
    };

    logReceivedSpansIncludeAllAttrs = mkOption {
      type = bool;
      default = false;
    };

    logReceivedSpansFilterByStatusError = mkOption {
      type = bool;
      default = false;
    };

    searchTagsDenyList = mkOption {
      type = nullOr (listOf str);
      default = null;
    };

    ingesterLifecyclerRingRepl = mkOption {
      type = ints.positive;
      default = 1;
    };

    metricsGeneratorEnable = mkOption {
      type = bool;
      default = true;
      description = ''
        The metrics-generator processes spans and write metrics using
        the Prometheus remote write protocol.
      '';
    };

    metricsGeneratorStoragePath = mkOption {
      type = str;
      default = "/var/lib/tempo/storage/wal-metrics";
      description = ''
        Path to store the WAL. Each tenant will be stored in its own subdirectory.
      '';
    };

    metricsGeneratorStorageRemoteWrite = mkOption {
      type = listOf attrs;
      default = [{url = "http://127.0.0.1:8428/api/v1/write";}];
      description = ''
        A list of remote write endpoints in Prometheus remote_write format:
        https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write
      '';
    };

    compactorCompactionBlockRetention = mkOption {
      type = str;
      default = "336h";
      description = "Duration to keep blocks.  Default is 14 days.";
    };

    storageTraceBackend = mkOption {
      type = enum ["local" "s3"];
      default = "s3";
      description = ''
        The storage backend to use.
      '';
    };

    storageLocalPath = mkOption {
      type = str;
      default = "/var/lib/tempo/storage/local";
      description = ''
        Where to store state if the backend selected is "local".
      '';
    };

    storageS3Bucket = mkOption {
      type = str;
      default = config.cluster.s3BucketTempo;
      description = ''
        Bucket name in s3.  Tempo requires a dedicated bucket since it maintains a top-level
        object structure and does not support a custom prefix to nest within a shared bucket.
      '';
    };

    storageS3Endpoint = mkOption {
      type = nullOr str;
      default = "s3.${config.cluster.region}.amazonaws.com";
      description = ''
        Api endpoint to connect to.  Use AWS S3 or any S3 compatible object storage endpoint.
        Prem/minio usage will require customizing this option.
      '';
    };

    storageS3AccessCredsEnable = mkOption {
      type = bool;
      default = false;
      description = ''
        Whether to enable access key ENV VAR usage for static credentials.
        Required for prem/minio usage.

        If enabled, an encrypted file is expected to exist containing the following substituted lines:

        AWS_ACCESS_KEY_ID=$SECRET_KEY_ID
        AWS_SECRET_ACCESS_KEY=$SECRET_KEY
      '';
    };

    storageS3ForcePathStyle = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable to use path-style requests.  Required for prem/minio usage.
      '';
    };

    storageS3Insecure = mkOption {
      type = bool;
      default = false;
      description = ''
        Debugging option for temporary http testing.
      '';
    };

    storageS3InsecureSkipVerify = mkOption {
      type = bool;
      default = false;
      description = ''
        Debugging option for temporary https testing.
      '';
    };

    storageTraceWalPath = mkOption {
      type = str;
      default = "/var/lib/tempo/storage/wal";
      description = ''
        Where to store the head blocks while they are being appended to.
      '';
    };

    searchEnable = mkOption {
      type = bool;
      default = true;
      description = ''
        Enable tempo search.
      '';
    };

    extraConfig = mkOption {
      type = attrs;
      default = {};
      description = ''
        Extra configuration to pass to Tempo service.
        See https://grafana.com/docs/tempo/latest/configuration/ for available options.
      '';
    };
  };

  config = mkIf cfg.enable {
    # for tempo-cli and friends
    environment.systemPackages = [pkgs.tempo];

    networking.firewall.allowedTCPPorts =
      [
        cfg.httpListenPort # default: 3200
        cfg.grpcListenPort # default: 9096
      ]
      # Tempo receiver port references:
      # https://github.com/open-telemetry/opentelemetry-collector/blob/main/receiver/otlpreceiver/README.md
      # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/jaegerreceiver
      # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/opencensusreceiver
      # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/zipkinreceiver
      ++ optionals cfg.receiverOtlpGrpc [4317]
      ++ optionals cfg.receiverOtlpHttp [4318]
      ++ optionals cfg.receiverZipkin [9411]
      ++ optionals cfg.receiverJaegerGrpc [14250]
      ++ optionals cfg.receiverJaegerThriftHttp [14268]
      ++ optionals cfg.receiverOpencensus [55678];

    networking.firewall.allowedUDPPorts =
      []
      # Tempo receiver port references:
      # https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/jaegerreceiver
      ++ optionals cfg.receiverJaegerThriftCompact [6831]
      ++ optionals cfg.receiverJaegerThriftBinary [6832];

    services.memcached = mkIf cfg.memcachedEnable {
      enable = true;
      maxMemory = cfg.memcachedMaxMb;
    };

    systemd.services =
      {
        tempo = {
          description = "Grafana Tempo Service Daemon";
          wantedBy = ["multi-user.target"];

          serviceConfig = let
            mkTempoReceiver = opt: receiver:
              if opt
              then flip recursiveUpdate receiver
              else flip recursiveUpdate {};

            settings =
              recursiveUpdate {
                server = {
                  http_listen_address = cfg.httpListenAddress;
                  http_listen_port = cfg.httpListenPort;
                  grpc_listen_port = cfg.grpcListenPort;
                };

                distributor = {
                  receivers = pipe {} [
                    (mkTempoReceiver cfg.receiverOtlpHttp {otlp.protocols.http = null;})
                    (mkTempoReceiver cfg.receiverOtlpGrpc {otlp.protocols.grpc = null;})
                    (mkTempoReceiver cfg.receiverJaegerThriftHttp {jaeger.protocols.thrift_http = null;})
                    (mkTempoReceiver cfg.receiverJaegerGrpc {jaeger.protocols.grpc = null;})
                    (mkTempoReceiver cfg.receiverJaegerThriftBinary {jaeger.protocols.thrift_binary = null;})
                    (mkTempoReceiver cfg.receiverJaegerThriftCompact {jaeger.protocols.thrift_compact = null;})
                    (mkTempoReceiver cfg.receiverZipkin {zipkin = null;})
                    (mkTempoReceiver cfg.receiverOpencensus {opencensus = null;})
                    (mkTempoReceiver cfg.receiverKafka {kafka = null;})
                  ];

                  log_received_spans = {
                    enabled = cfg.logReceivedSpansEnable;
                    include_all_attributes = cfg.logReceivedSpansIncludeAllAttrs;
                    filter_by_status_error = cfg.logReceivedSpansFilterByStatusError;
                  };

                  search_tags_deny_list = cfg.searchTagsDenyList;
                };

                ingester.lifecycler.ring.replication_factor = cfg.ingesterLifecyclerRingRepl;

                metrics_generator_enabled = cfg.metricsGeneratorEnable;
                metrics_generator.storage = {
                  path = cfg.metricsGeneratorStoragePath;
                  remote_write = cfg.metricsGeneratorStorageRemoteWrite;
                };

                compactor.compaction.block_retention = cfg.compactorCompactionBlockRetention;

                storage.trace =
                  {
                    backend = cfg.storageTraceBackend;
                    local.path = cfg.storageLocalPath;
                    wal.path = cfg.storageTraceWalPath;
                  }
                  // optionalAttrs (cfg.memcachedEnable) {
                    cache = "memcached";
                    memcached = let
                      inherit (config.services.memcached) port;
                    in {
                      addresses = "tempo-memcached.service.consul:${toString port}";
                    };
                  }
                  // optionalAttrs (cfg.storageTraceBackend == "s3") {
                    s3 =
                      {
                        bucket = cfg.storageS3Bucket;
                        endpoint = cfg.storageS3Endpoint;

                        # For temporary debug:
                        insecure = cfg.storageS3Insecure;
                        insecure_skip_verify = cfg.storageS3InsecureSkipVerify;

                        # Primarily for prem/minio use:
                        forcepathstyle = cfg.storageS3ForcePathStyle;
                      }
                      // optionalAttrs cfg.storageS3AccessCredsEnable
                      {
                        access_key = "\${AWS_ACCESS_KEY_ID}";
                        secret_key = "\${AWS_SECRET_ACCESS_KEY}";
                      };
                  };

                search_enabled = cfg.searchEnable;
              }
              cfg.extraConfig;

            script = pkgs.writeShellApplication {
              name = "tempo.sh";
              text = ''
                ${
                  if cfg.storageS3AccessCredsEnable
                  then ''
                    while ! [ -s ${runKeyMaterial.tempo} ]; do
                      echo "Waiting for ${runKeyMaterial.tempo}..."
                      sleep 3
                    done

                    set -a
                    # shellcheck disable=SC1091
                    source ${runKeyMaterial.tempo}
                    set +a''
                  else ""
                }

                exec ${pkgs.tempo}/bin/tempo --config.expand-env --config.file=${conf}
              '';
            };

            conf = settingsFormat.generate "config.yaml" settings;
          in {
            ExecStart = "${script}/bin/tempo.sh";
            DynamicUser = true;
            Restart = "always";
            ProtectSystem = "full";
            DevicePolicy = "closed";
            NoNewPrivileges = true;
            WorkingDirectory = "/var/lib/tempo";
            StateDirectory = "tempo";
          };
        };
      }
      // (let
        registerConsulService = service: flip recursiveUpdate service;
        mkConsulService = cond: name: port: protocol: dep:
          if cond
          then {
            "${name}" =
              (pkgs.consulRegister {
                pkiFiles = {inherit caCertFile;};
                systemdServiceDep = dep;
                service = {
                  inherit name port;

                  checks = {
                    "${name}-${protocol}" = {
                      interval = "10s";
                      timeout = "5s";
                      "${protocol}" = "127.0.0.1:${toString port}";
                    };
                  };
                };
              })
              .systemdService;
          }
          else {};
      in
        pipe {} [
          (registerConsulService (mkConsulService cfg.receiverOtlpGrpc "tempo-otlp-grpc" 4317 "tcp" "tempo"))
          (registerConsulService (mkConsulService cfg.receiverOtlpHttp "tempo-otlp-http" 4318 "tcp" "tempo"))
          (registerConsulService (mkConsulService cfg.receiverZipkin "tempo-zipkin" 9411 "tcp" "tempo"))
          (registerConsulService (mkConsulService cfg.receiverJaegerGrpc "tempo-jaeger-grpc" 14250 "tcp" "tempo"))
          (registerConsulService (mkConsulService cfg.receiverJaegerThriftHttp "tempo-jaeger-thrift-http" 14268 "tcp" "tempo"))
          (registerConsulService (mkConsulService cfg.receiverOpencensus "tempo-opencensus" 55678 "tcp" "tempo"))
          # TODO: UDP checks not yet supported
          # Ref: https://github.com/hashicorp/nomad/issues/14094
          #
          # (registerConsulService (mkConsulService cfg.receiverJaegerThriftCompact "tempo-jaeger-thrift-compact" 6831 "udp" "tempo"))
          # (registerConsulService (mkConsulService cfg.receiverJaegerThriftBinary "tempo-jaeger-thrift-binary" 6832 "udp" "tempo"))
          #
          # Kafka receiver will depend on specific configuration
        ])
      // optionalAttrs cfg.memcachedEnable {
        # Tempo appears to force use of a DNS based discovery mechanism despite memcached being a localhost service
        memcached-service =
          (pkgs.consulRegister {
            pkiFiles = {inherit caCertFile;};
            systemdServiceDep = "memcached";
            service = let
              inherit (config.services.memcached) port;
            in {
              name = "tempo-memcached";
              inherit port;

              address = "127.0.0.1";
              checks = {
                memcached-tcp = {
                  interval = "10s";
                  timeout = "5s";
                  tcp = "127.0.0.1:${toString port}";
                };
              };
            };
          })
          .systemdService;
      };

    secrets = mkIf (cfg.storageS3AccessCredsEnable && isSops) {
      install.tempo = {
        inputType = "binary";
        outputType = "binary";
        source = config.secrets.encryptedRoot + "/tempo";
        target = runKeyMaterial.tempo;
        script = ''
          chmod 0600 ${runKeyMaterial.tempo}
          chown tempo:tempo ${runKeyMaterial.tempo}
        '';
        #  # File format for tempo secret file
        #  AWS_ACCESS_KEY_ID=$SECRET_KEY_ID
        #  AWS_SECRET_ACCESS_KEY=$SECRET_KEY
      };
    };

    age.secrets = mkIf (cfg.storageS3AccessCredsEnable && !isSops) {
      tempo = {
        file = config.age.encryptedRoot + "/monitoring/tempo.age";
        path = runKeyMaterial.tempo;
        owner = "tempo";
        group = "tempo";
        mode = "0600";
        #  # File format for tempo secret file
        #  AWS_ACCESS_KEY_ID=$SECRET_KEY_ID
        #  AWS_SECRET_ACCESS_KEY=$SECRET_KEY
      };
    };
  };
}
