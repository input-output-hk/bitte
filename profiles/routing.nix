{ self, lib, pkgs, config, ... }: {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./secrets.nix
    ./telegraf.nix
    ./vault/client.nix
  ];

  services.amazon-ssm-agent.enable = true;

  services.vault-agent-core = {
    enable = true;
    vaultAddress = "https://${config.cluster.instances.core-1.privateIP}:8200";
  };

  systemd.services.copy-acme-certs = {
    before = [ "traefik.service" ];
    wantedBy = [ "traefik.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
    };

    path = [ pkgs.coreutils ];

    script = ''
      set -exuo pipefail

      mkdir -p /var/lib/traefik/certs
      cp /etc/ssl/certs/${config.cluster.domain}-*.pem /var/lib/traefik/certs
      chown -R traefik:traefik /var/lib/traefik
    '';
  };

  services.traefik = {
    enable = true;

    dynamicConfigOptions = {
      tls.certificates = [{
        certFile = "/var/lib/traefik/certs/${config.cluster.domain}-full.pem";
        keyFile = "/var/lib/traefik/certs/${config.cluster.domain}-key.pem";
      }];

      http = {
        routers = {
          traefik = {
            rule = "Host(`routing.${config.cluster.domain}`)";
            service = "api@internal";
            entrypoints = "https";
            tls = true;
          };
        };
      };
    };

    staticConfigOptions = {
      metrics.influxDB = {
        address =
          "http://${config.cluster.instances.monitoring.privateIP}:8428";
        protocol = "http";
        database = "traefik";
        addEntryPointsLabels = true;
        addServicesLabels = true;
        pushInterval = "10s";
      };

      api = { dashboard = true; };

      entryPoints = {
        http = {
          address = ":80";
          http = {
            redirections = {
              entryPoint = {
                scheme = "https";
                to = "https";
              };
            };
          };
        };

        https = { address = ":443"; };
      };

      providers.consulCatalog = {
        refreshInterval = "30s";

        prefix = "traefik";

        # Forces the read to be fully consistent.
        requireConsistent = true;

        # Use stale consistency for catalog reads.
        stale = false;

        # Use local agent caching for catalog reads.
        cache = false;

        endpoint = {
          # Defines the address of the Consul server.
          address = "127.0.0.1:${config.services.consul.ports.http}";

          scheme = "http";

          # Defines the datacenter to use. If not provided in Traefik, Consul uses the default agent datacenter.
          datacenter = config.cluster.region;

          # Token is used to provide a per-request ACL token which overwrites the agent's default token.
          # token = ""

          # Limits the duration for which a Watch can block. If not provided, the agent default values will be used.
          # endpointWaitTime = "1s";
        };

        # Expose Consul Catalog services by default in Traefik. If set to false, services that don't have a traefik.enable=true tag will be ignored from the resulting routing configuration.
        exposedByDefault = false;

        # The default host rule for all services.
        # For a given service, if no routing rule was defined by a tag, it is
        # defined by this defaultRule instead. The defaultRule must be set to a
        # valid Go template, and can include sprig template functions. The
        # service name can be accessed with the Name identifier, and the template
        # has access to all the labels (i.e. tags beginning with the prefix)
        # defined on this service.
        # The option can be overridden on an instance basis with the
        # traefik.http.routers.{name-of-your-choice}.rule tag.
        # Default=Host(`{{ normalize .Name }}`)
        # defaultRule = ''Host(`{{ .Name }}.{{ index .Labels "customLabel"}}`)'';
        defaultRule = "Host(`{{ normalize .Name }}`)";

        # The constraints option can be set to an expression that Traefik matches
        # against the service tags to determine whether to create any route for that
        # service. If none of the service tags match the expression, no route for that
        # service is created. If the expression is empty, all detected services are
        # included.
        # The expression syntax is based on the Tag(`tag`), and TagRegex(`tag`)
        # functions, as well as the usual boolean logic.
        constraints = "Tag(`ingress`)";
      };
    };
  };
}
