{ ... }: {
  services.promtail = {
    enable = true;

    server = {
      http_listen_port = 2101;
      grpc_listen_port = 0;
    };

    clients = [{ url = "http://monitoring:3100/loki/api/v1/push"; }];

    positions = { filename = "/var/lib/promtail/positions.yaml"; };
  };
}
