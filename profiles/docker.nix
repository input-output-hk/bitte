{ config, ... }: {
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "daily";
    };

    extraOptions = ''
      --log-driver=journald
    '';
  };

  # needed to access AWS meta-data after docker starts veth* devices.
  networking.interfaces.ens5.ipv4.routes = [{
    address = "169.254.169.252";
    prefixLength = 30;
  }];

  environment.etc."/docker/certs.d/docker.${config.cluster.domain}/ca.crt".source =
    ./acme-staging-root.pem;
}
