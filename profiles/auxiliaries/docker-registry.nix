{ lib, pkgs, config, etcEncrypted, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  isSops = deployType == "aws";
  relEncryptedFolder = lib.last (builtins.split "-" (toString config.secrets.encryptedRoot));
in {

  networking.firewall.allowedTCPPorts = [
    config.services.dockerRegistry.port
  ];

  services = {
    dockerRegistry = {
      enable = lib.mkDefault true;
      enableDelete = true;
      enableGarbageCollect = true;
      enableRedisCache = true;
      listenAddress = "0.0.0.0";

      extraConfig.redis = {
        addr = "${config.services.dockerRegistry.redisUrl}";
        password = "${config.services.dockerRegistry.redisPassword}";
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

  systemd.services.docker-registry-service =
    (pkgs.consulRegister {
      pkiFiles.caCertFile = "/etc/ssl/certs/ca.pem";
      service = {
        name = "docker-registry";
        port = config.services.dockerRegistry.port;
        tags = [
          "ingress"
          "traefik.enable=true"
          "traefik.http.routers.docker-registry-auth.rule=Host(`registry.ci.iog.io`)"
          "traefik.http.routers.docker-registry-auth.entrypoints=https"
          "traefik.http.routers.docker-registry-auth.tls=true"
          "traefik.http.routers.docker-registry-auth.tls.certresolver=acme"
          "traefik.http.routers.docker-registry-auth.middlewares=docker-registry-auth"
          "traefik.http.middlewares.docker-registry-auth.basicauth.usersfile=/var/lib/traefik/basic-auth"
          "traefik.http.middlewares.docker-registry-auth.basicauth.realm=Registry"
          "traefik.http.middlewares.docker-registry-auth.basicauth.removeheader=true"
        ];

        checks = {
          docker-registry-tcp = {
            interval = "10s";
            timeout = "5s";
            tcp = "127.0.0.1:${toString config.services.dockerRegistry.port}";
          };
        };
      };
    })
    .systemdService;

  secrets.generate.redis-password = lib.mkIf isSops ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils sops xkcdpass ])}"

    if [ ! -s ${relEncryptedFolder}/redis-password.json ]; then
      xkcdpass \
      | sops --encrypt --kms '${config.cluster.kms}' /dev/stdin \
      > ${relEncryptedFolder}/redis-password.json
    fi
  '';

  secrets.install.redis-password = lib.mkIf isSops {
    source = "${etcEncrypted}/redis-password.json";
    target = /run/keys/redis-password;
    inputType = "binary";
    outputType = "binary";
  };

  # For the prem case, hydrate-secrets handles the push to vault instead of sops
  # TODO: add proper docker password generation creds in the Rakefile
  # TODO: add more unified handling between aws and prem secrets
  age.secrets = lib.mkIf (!isSops) {
    redis-password = {
      file = config.age.encryptedRoot + "/redis/password.age";
      path = "/run/keys/redis-password";
      owner = "root";
      group = "root";
      mode = "0644";
    };
  };
}
