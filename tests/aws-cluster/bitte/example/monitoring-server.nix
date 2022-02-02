{ config, ... }: {
  #imports = [ ./github-secrets.nix ];

  networking.firewall.allowedUDPPorts = [ 17777 ];

  ########
  services.grafana.provision.dashboards = [{
    name = "provisioned-aws-cluster";
    # todo: add real dashboard
    options.path = ../../secrets;
  }];

  services.loki.configuration.table_manager = {
    retention_deletes_enabled = true;
    retention_period = "14d";
  };

  #services.vulnix = {
  #  scanNomadJobs.enable = true;
  #};

  services.ingress-config = {
    extraConfig = ''
      backend hydra
        default-server check maxconn 2000
        http-request set-header X-Forwarded-Proto "https"
        option httpchk HEAD /
        server hydra ${config.cluster.coreNodes.hydra.privateIP}:3001
    '';

    extraHttpsAcls = ''
      acl is_hydra hdr(host) -i hydra.${config.cluster.domain}
    '';

    extraHttpsBackends = ''
      use_backend hydra if is_hydra  authenticated
      use_backend oauth_proxy if is_hydra  ! authenticated
    '';
  };
}
