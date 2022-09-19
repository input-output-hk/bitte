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

  cfg = config.services.monitoring;
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
  ];

  services = {
    monitoring.enable = mkDefault true;
    loki.enable = mkDefault true;
    minio.enable = mkDefault true;
    nomad.enable = false;

    vmagent.promscrapeConfig = mkIf (config.services.vmagent.enable && cfg.useTempo) [
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
}
