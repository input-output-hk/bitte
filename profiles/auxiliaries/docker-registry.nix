{ lib, pkgs, config, ... }: {
  systemd.services.docker-registry.serviceConfig.Environment = [
    "REGISTRY_AUTH=htpasswd"
    "REGISTRY_AUTH_HTPASSWD_REALM=docker-registry"
    "REGISTRY_AUTH_HTPASSWD_PATH=/var/lib/docker-registry/docker-passwords"
  ];

  services = {
    dockerRegistry = {
      enable = true;
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

  secrets.generate.redis-password = ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils sops xkcdpass ])}"

    if [ ! -s encrypted/redis-password.json ]; then
      xkcdpass \
      | sops --encrypt --kms '${config.cluster.kms}' /dev/stdin \
      > encrypted/redis-password.json
    fi
  '';

  secrets.install.redis-password = {
    source = (toString config.secrets.encryptedRoot) + "/redis-password.json";
    target = /run/keys/redis-password;
    inputType = "binary";
    outputType = "binary";
  };

  secrets.generate.docker-passwords = ''
    export PATH="${
      lib.makeBinPath (with pkgs; [ coreutils sops jq pwgen apacheHttpd ])
    }"

    if [ ! -s encrypted/docker-passwords.json ]; then
      password="$(pwgen -cB 32)"
      hashed="$(echo "$password" | htpasswd -i -B -n developer)"

      echo '{}' \
        | jq --arg password "$password" '.password = $password' \
        | jq --arg hashed "$hashed" '.hashed = $hashed' \
        | sops --encrypt --input-type json --output-type json --kms '${config.cluster.kms}' /dev/stdin \
        > encrypted/docker-passwords.new.json
      mv encrypted/docker-passwords.new.json encrypted/docker-passwords.json
    fi
  '';

  secrets.install.docker-passwords = {
    source = (toString config.secrets.encryptedRoot) + "/docker-passwords.json";
    target = /run/keys/docker-passwords-decrypted;
    script = ''
      export PATH="${lib.makeBinPath (with pkgs; [ coreutils jq ])}"

      jq -r -e < /run/keys/docker-passwords-decrypted .hashed \
        > /var/lib/docker-registry/docker-passwords
      chown docker-registry /var/lib/docker-registry/docker-passwords
    '';
  };
}
