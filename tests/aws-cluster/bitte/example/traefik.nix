{ self, lib, pkgs, config, ... }:
let
  domain = config.cluster.domain;

  publicPortMappings = lib.pipe
    {
      example-testnet = 10000;
      #example-testnet = 11000;
    } [
    (lib.mapAttrsToList (namespace: port:
      (lib.genList
        (n: [
          {
            name = "${namespace}-server-${toString n}";
            value.address = ":${toString (port + n)}";
          }
          {
            name = "${namespace}-other-service-${toString n}";
            value.address = ":${toString (port + n)}";
          }
        ]) 3)
      ))
    lib.concatLists
    lib.concatLists
    lib.listToAttrs
  ];
in
{

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
          #hydra = {
          #  entrypoints = "https";
          #  middlewares = [ "oauth-auth-redirect" ];
          #  rule = "Host(`hydra.${domain}`) && PathPrefix(`/`)";
          #  service = "hydra";
          #  tls = true;
          #};

          #hydra-plain = {
          #  entrypoints = "https";
          #  middlewares = [ ];
          #  rule = "Host(`hydra.${domain}`) && (PathPrefix(`/nar/`) || Path(`/{hash:[a-z0-9]{32}}.narinfo`) || PathPrefix(`/nix-cache-info`))";
          #  service = "hydra";
          #  tls = true;
          #};

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

          traefik-oauth2-route = {
            entrypoints = "https";
            middlewares = [ "auth-headers" ];
            rule = "Host(`traefik.${domain}`) && PathPrefix(`/oauth2/`)";
            service = "oauth-backend";
            tls = true;
          };

          #hydra-oauth2-route = {
          #  entrypoints = "https";
          #  middlewares = [ "auth-headers" ];
          #  rule = "Host(`hydra.${domain}`) && PathPrefix(`/oauth2/`)";
          #  service = "oauth-backend";
          #  tls = true;
          #};
        };

        services = {
          oauth-backend = {
            loadBalancer = { servers = [{ url = "http://127.0.0.1:4180"; }]; };
          };

          #hydra = {
          #  loadBalancer = { servers = [{ url = "http://${config.cluster.instances.hydra.privateIP}:3001"; }]; };
          #};
        };
      };
    };

    staticConfigOptions = {
      accesslog = true;
      log.level = "info";

      api = { dashboard = true; };

      entryPoints = publicPortMappings // {
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
