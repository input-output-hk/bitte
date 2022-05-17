{ lib, config, ... }: {
  services.promtail = lib.mkIf (config.cluster.nodes ? monitoring) {
    enable = true;

    clients = [{
      url =
        "http://${config.cluster.nodes.monitoring.privateIP}:3100/loki/api/v1/push";
    }];
  };
}
