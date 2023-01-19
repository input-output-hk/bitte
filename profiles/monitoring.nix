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
  isSops = builtins.elem deployType ["aws" "awsExt"];

  cfg = config.services.monitoring;
in {
  imports = [
    # Profiles -- ungated config mutation w/o options
    ./common.nix
    ./consul/client.nix
    ./vault/monitoring.nix

    # Modules -- enable gated config mutation w/ options
    ../modules/grafana.nix
    ../modules/monitoring.nix
  ];

  services = {
    monitoring.enable = mkDefault true;
    loki.enable = mkDefault true;
    minio.enable = mkDefault true;
    nomad.enable = false;
  };
}
