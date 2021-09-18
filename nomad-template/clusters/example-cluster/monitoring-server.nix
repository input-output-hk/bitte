{ ... }: {
  services.grafana.provision.dashboards = [{
    name = "provisioned-example";
    options.path = ../../../contrib/dashboards;
  }];

  services.loki.configuration.table_manager = {
    retention_deletes_enabled = true;
    retention_period = "14d";
  };

  services.ingress-config = {
    extraConfig = "";
    extraHttpsBackends = "";
  };
}
