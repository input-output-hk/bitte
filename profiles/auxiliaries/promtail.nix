_: {
  services.promtail.enable = true;

  services.promtail.clients = [{
    url =
      "http://${config.cluster.nodes.monitoring.privateIP}:3100/loki/api/v1/push";
  }];
}
