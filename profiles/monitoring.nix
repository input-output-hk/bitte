{
  config,
  pkgs,
  lib,
  pkiFiles,
  runKeyMaterial,
  ...
}: let
  inherit (lib) flip mkDefault mkIf pipe recursiveUpdate;
  inherit (pkiFiles) caCertFile;

  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  isSops = deployType == "aws";

  cfgTempo = config.services.tempo;
in {
  imports = [
    # Profiles -- ungated config mutation w/o options
    ./common.nix
    ./consul/client.nix
    ./vault/monitoring.nix
    ./auxiliaries/loki.nix

    # Modules -- enable gated config mutation w/ options
    ../modules/grafana.nix
    ../modules/monitoring.nix
    ../modules/tempo.nix
  ];

  services = {
    monitoring.enable = mkDefault true;
    loki.enable = mkDefault true;
    minio.enable = mkDefault true;
    nomad.enable = false;

    vmagent.promscrapeConfig = mkIf config.services.vmagent.enable [
      {
        job_name = "tempo";
        scrape_interval = "60s";
        metrics_path = "/metrics";
        static_configs = [
          {
            targets = ["${cfgTempo.httpListenAddress}:${toString cfgTempo.httpListenPort}"];
            labels.alias = "tempo";
          }
        ];
      }
    ];

    tempo = {
      enable = mkDefault true;
      metricsGeneratorStorageRemoteWrite = mkDefault [{url = "http://${config.services.victoriametrics.httpListenAddr}/api/v1/write";}];
      storageS3Bucket = config.cluster.s3BucketTempo;
      storageS3Endpoint = mkDefault "s3.${config.cluster.region}.amazonaws.com";
      storageS3AccessCredsPath = mkDefault runKeyMaterial.tempo;
      storageTraceBackend = mkDefault "s3";
    };
  };

  systemd.services = let
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
      (registerConsulService (mkConsulService cfgTempo.receiverOtlpGrpc "tempo-otlp-grpc" 4317 "tcp" "tempo"))
      (registerConsulService (mkConsulService cfgTempo.receiverOtlpHttp "tempo-otlp-http" 4318 "tcp" "tempo"))
      (registerConsulService (mkConsulService cfgTempo.receiverZipkin "tempo-zipkin" 9411 "tcp" "tempo"))
      (registerConsulService (mkConsulService cfgTempo.receiverJaegerGrpc "tempo-jaeger-grpc" 14250 "tcp" "tempo"))
      (registerConsulService (mkConsulService cfgTempo.receiverJaegerThriftHttp "tempo-jaeger-thrift-http" 14268 "tcp" "tempo"))
      (registerConsulService (mkConsulService cfgTempo.receiverOpencensus "tempo-opencensus" 55678 "tcp" "tempo"))
      # TODO: UDP checks not yet supported
      # Ref: https://github.com/hashicorp/nomad/issues/14094
      #
      # (registerConsulService (mkConsulService cfgTempo.receiverJaegerThriftCompact "tempo-jaeger-thrift-compact" 6831 "udp" "tempo"))
      # (registerConsulService (mkConsulService cfgTempo.receiverJaegerThriftBinary "tempo-jaeger-thrift-binary" 6832 "udp" "tempo"))
      #
      # Kafka receiver will depend on specific configuration
    ];

  secrets = mkIf (cfgTempo.storageS3AccessCredsEnable && isSops) {
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

  age.secrets = mkIf (cfgTempo.storageS3AccessCredsEnable && !isSops) {
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
}
