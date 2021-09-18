{ self, lib, pkgs, config, ... }:
let domain = config.cluster.domain;
in {
  imports = [
    (self.inputs.bitte + /profiles/common.nix)
    (self.inputs.bitte + /profiles/consul/client.nix)
    (self.inputs.bitte + /profiles/secrets.nix)
    (self.inputs.bitte + /profiles/telegraf.nix)
    (self.inputs.bitte + /profiles/vault/client.nix)
    ./secrets.nix
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
      RemainAfterExit = lib.mkForce true;
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

  services.oauth2_proxy.extraConfig.skip-provider-button = "true";
  services.oauth2_proxy.extraConfig.upstream = "static://202";

  services.traefik = {
    enable = true;

    dynamicConfigOptions = {
      http = {
        middlewares = {
          auth-headers = {
            headers = {
              browserXssFilter = true;
              contentTypeNosniff = true;
              forceSTSHeader = true;
              frameDeny = true;
              sslHost = domain;
              sslRedirect = true;
              stsIncludeSubdomains = true;
              stsPreload = true;
              stsSeconds = 315360000;
            };
          };

          oauth-auth-redirect = {
            forwardAuth = {
              address = "https://oauth.${domain}/";
              authResponseHeaders =
                [ "X-Auth-Request-Access-Token" "Authorization" ];
              trustForwardHeader = true;
            };
          };
        };

        routers = lib.mkForce {
          traefik = {
            entrypoints = "https";
            middlewares = [ "oauth-auth-redirect" ];
            rule = "Host(`traefik.${domain}`) && PathPrefix(`/`)";
            service = "api@internal";
            tls = true;
          };

          oauth2-proxy-route = {
            entrypoints = "https";
            middlewares = [ "auth-headers" ];
            rule = "Host(`oauth.${domain}`) && PathPrefix(`/`)";
            service = "oauth-backend";
            tls = true;
          };

          services-oauth2-route = {
            entrypoints = "https";
            middlewares = [ "auth-headers" ];
            rule = "Host(`traefik.${domain}`) && PathPrefix(`/oauth2/`)";
            service = "oauth-backend";
            tls = true;
          };
        };

        services = {
          oauth-backend = {
            loadBalancer = { servers = [{ url = "http://127.0.0.1:4180"; }]; };
          };
        };
      };
    };

    staticConfigOptions = {
      accesslog = true;
      log.level = "info";

      api = { dashboard = true; };

      entryPoints = let
        publicPortMappings = lib.pipe { example-cluster = 9001; } [
          (lib.mapAttrsToList (namespace: port:
            lib.genList (n: [
              {
                name = "${namespace}-discovery-${toString n}";
                value.address = ":${toString (port + 500 + n)}";
              }
              {
                name = "${namespace}-server-${toString n}";
                value.address = ":${toString (port + n)}";
              }
            ]) 5))
          lib.concatLists
          lib.concatLists
          lib.listToAttrs
        ];

      in publicPortMappings // {
        http = {
          address = ":80";
          forwardedHeaders.insecure = true;
          http = {
            redirections = {
              entryPoint = {
                scheme = "https";
                to = "https";
              };
            };
          };
        };

        https = {
          address = ":443";
          forwardedHeaders.insecure = true;
        };
      };
    };
  };
}
