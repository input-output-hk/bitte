{
  lib,
  pkgs,
  config,
  etcEncrypted,
  runKeyMaterial,
  pkiFiles,
  ...
}: let
  inherit (lib) boolToString last makeBinPath mkDefault mkEnableOption mkIf mkOption;
  inherit (lib.types) bool listOf package str;
  inherit (lib.types.ints) unsigned;
  inherit (pkiFiles) caCertFile;

  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  domain =
    config
    .${
      if builtins.elem deployType ["aws" "awsExt"]
      then "cluster"
      else "currentCoreNode"
    }
    .domain;
  isSops = builtins.elem deployType ["aws" "awsElem"];
  relEncryptedFolder = last (builtins.split "-" (toString config.secrets.encryptedRoot));
  cfg = config.services.docker-registry;
in {
  options.services.docker-registry = {
    enable = mkEnableOption "Docker registry";

    registryFqdn = mkOption {
      type = str;
      default = "registry.${domain}";
      description = "The default host fqdn for the traefik routed registry service.";
    };

    traefikTags = mkOption {
      type = listOf str;
      default = [
        "ingress"
        "traefik.enable=true"
        "traefik.http.routers.docker-registry-auth.rule=Host(`${cfg.registryFqdn}`)"
        "traefik.http.routers.docker-registry-auth.entrypoints=https"
        "traefik.http.routers.docker-registry-auth.tls=true"
        "traefik.http.routers.docker-registry-auth.tls.certresolver=acme"
        "traefik.http.routers.docker-registry-auth.middlewares=docker-registry-auth"
        "traefik.http.middlewares.docker-registry-auth.basicauth.usersfile=/var/lib/traefik/basic-auth"
        "traefik.http.middlewares.docker-registry-auth.basicauth.realm=Registry"
        "traefik.http.middlewares.docker-registry-auth.basicauth.removeheader=true"
      ];
      description = ''
        Sets the traefik tags for the docker registry to use.
        With the default module option traefik tags, traefik routing server requires
        a basic-auth file for registry authentication.
      '';
    };

    enableRepair = mkOption {
      type = bool;
      default = true;
      description = "Enables the docker registry repair service.";
    };

    repairDeleteTag = mkOption {
      type = bool;
      default = false;
      description = "Also delete all tag references during repair.";
    };

    repairDryRun = mkOption {
      type = bool;
      default = false;
      description = "Avoid deleting anything during repair.";
    };

    repairPkg = mkOption {
      type = package;
      default = pkgs.docker-registry-repair;
      description = ''
        The registry repair package to utilize.
        Assumes a bin file of ''${cfg.repairPkg}/bin/docker-registry-repair.
      '';
    };

    repairRegistryPath = mkOption {
      type = str;
      default = "/var/lib/docker-registry/docker/registry/v2";
      description = "The registry path.";
    };

    repairTailDelay = mkOption {
      type = unsigned;
      default = 5;
      description = "The time delay in seconds between repair spawn jobs.";
    };

    repairTailLookback = mkOption {
      type = str;
      default = "-1h";
      description = ''
        The lookback period for journal history.
        This needs to be a valid journalctl -S parameter formatted string.
      '';
    };

    repairTailPkg = mkOption {
      type = package;
      default = pkgs.docker-registry-tail;
      description = ''
        The registry repair tail package to utilize.
        Assumes a bin file of ''${cfg.repairTailPkg}/bin/docker-registry-tail.
      '';
    };

    repairTailService = mkOption {
      type = str;
      default = "docker-registry.service";
      description = "The systemd service to tail.";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [
      config.services.dockerRegistry.port
    ];

    services = {
      dockerRegistry = {
        enable = mkDefault true;
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

      redis.servers.docker-redis = {
        enable = true;
        requirePassFile = runKeyMaterial.redis;
      };
    };

    systemd.services.docker-registry-service =
      (pkgs.consulRegister {
        pkiFiles = {inherit caCertFile;};
        service = {
          name = "docker-registry";
          port = config.services.dockerRegistry.port;
          tags = cfg.traefikTags;

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

    environment.systemPackages = with pkgs; [
      docker-registry-repair
      docker-registry-tail
    ];

    systemd.services.docker-registry-repair = mkIf cfg.enableRepair {
      wantedBy = ["multi-user.target"];

      startLimitIntervalSec = 0;
      startLimitBurst = 0;

      serviceConfig = {
        Restart = "always";
        RestartSec = 5;

        ExecStart = let
          script = pkgs.writeShellApplication {
            name = "docker-registry-repair-tail";
            text = ''
              exec ${cfg.repairTailPkg}/bin/docker-registry-tail \
                --since ${cfg.repairTailLookback} \
                --service ${cfg.repairTailService} \
                --repair-path ${cfg.repairPkg}/bin/docker-registry-repair \
                --delay ${toString cfg.repairTailDelay} \
                --delete-tag ${boolToString cfg.repairDeleteTag} \
                --dry-run ${boolToString cfg.repairDryRun}
            '';
          };
        in "${script}/bin/docker-registry-repair-tail";
      };
    };

    secrets.generate.redis-password = mkIf isSops ''
      export PATH="${makeBinPath (with pkgs; [coreutils sops xkcdpass])}"

      if [ ! -s ${relEncryptedFolder}/redis-password.json ]; then
        xkcdpass \
        | sops --encrypt --kms '${config.cluster.kms}' /dev/stdin \
        > ${relEncryptedFolder}/redis-password.json
      fi
    '';

    secrets.install.redis-password = mkIf isSops {
      source = "${etcEncrypted}/redis-password.json";
      target = runKeyMaterial.redis;
      inputType = "binary";
      outputType = "binary";
    };

    # For the prem case, hydrate-secrets handles the push to vault instead of sops
    # TODO: add proper docker password generation creds in the Rakefile
    # TODO: add more unified handling between aws and prem secrets
    age.secrets = mkIf (!isSops) {
      redis-password = {
        file = config.age.encryptedRoot + "/redis/password.age";
        path = runKeyMaterial.redis;
        owner = "root";
        group = "root";
        mode = "0644";
      };
    };
  };
}
