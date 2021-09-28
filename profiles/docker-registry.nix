{ lib, pkgs, config, ... }:
let inherit (config.cluster) kms;
in {
  systemd.services.docker-registry.serviceConfig.Environment = [
    "REGISTRY_AUTH=htpasswd"
    "REGISTRY_AUTH_HTPASSWD_REALM=docker-registry"
    "REGISTRY_AUTH_HTPASSWD_PATH=${config.age.secrets.docker-password.path}"
  ];

  services = {
    dockerRegistry = {
      enable = true;
      enableDelete = true;
      enableGarbageCollect = true;
      enableRedisCache = true;
      listenAddress = "0.0.0.0";

      extraConfig.redis = {
        addr = config.services.dockerRegistry.redisUrl;
        password = config.services.dockerRegistry.redisPassword;
        db = 0;
        dialtimeout = "10ms";
        readtimeout = "10ms";
        writetimeout = "10ms";
        pool = {
          maxidle = 16;
          maxactive = 64;
          idletimeout = "300s";
        };
      };
    };

    redis.enable = true;
  };

  age.secrets.docker-password = {
    file = config.secrets.encryptedRoot + "/docker/password.age";
    script = ''
      ${pkgs.apacheHttpd}/bin/htpasswd -i -B -n developer < $src > $out
    '';
  };
}
