{ lib, pkgs, config, nodeName, ... }: {
  imports = [ ../profiles/nomad ];

  services.nomad = {
    telemetry = {
      datadog_tags = [ "region:${config.cluster.region}" "role:nomad" ];
    };
  };
}
