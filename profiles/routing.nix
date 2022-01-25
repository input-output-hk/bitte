{ self, lib, pkgs, config, nodeName, bittelib, hashiTokens, letsencryptCertMaterial, pkiFiles, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  datacenter = config.currentCoreNode.datacenter or config.currentAwsAutoScalingGroup.datacenter;
  domain = config.${if deployType == "aws" then "cluster" else "currentCoreNode"}.domain;
  cfg = config.services.traefik;
in {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./vault/routing.nix

    ./auxiliaries/oauth.nix
  ];

  options.services.traefik = {
    prometheusPort = lib.mkOption {
      type = with lib.types; int;
      default = 9090;
      description =
        "The default port for traefik prometheus to publish metrics on.";
    };

    acmeDnsCertMgr = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        If true, acme systemd services will manage a single cert and provide it to traefik:
          - using dns Let's Encrypt challenge
          - using extraAcmeSANs which allow wildcards
          - utilizing route53 services
        If false, traefik will manage certs:
          - using http Let's Encrypt challenge
          - without other nameserver or DNS service depedencies
          - by obtaining individual certs for each traefik router service, including nomad job app routes
      '';
    };
  };

  config = {
    services.traefik.enable = true;
    services.consul.ui = true;

    networking.extraHosts = ''
      ${config.cluster.coreNodes.monitoring.privateIP} monitoring
    '';

    systemd.services.copy-acme-certs = lib.mkIf cfg.acmeDnsCertMgr {
      before = [ "traefik.service" ];
      wantedBy = [ "traefik.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        Restart = "on-failure";
        RestartSec = "30s";
      };

      path = [ pkgs.coreutils ];

      script = ''
        set -exuo pipefail

        mkdir -p /var/lib/traefik/certs
        cp ${letsencryptCertMaterial.certChainFile} /var/lib/traefik/certs/${builtins.baseNameOf letsencryptCertMaterial.certChainFile}
        cp ${letsencryptCertMaterial.keyFile} /var/lib/traefik/certs/${builtins.baseNameOf letsencryptCertMaterial.keyFile}

        chown -R traefik:traefik /var/lib/traefik
      '';
    };

    systemd.services."acme-${nodeName}".serviceConfig = lib.mkIf cfg.acmeDnsCertMgr {
      ExecStartPre = bittelib.ensureDependencies pkgs [ "vault-agent" ];
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    };

    security.acme = lib.mkIf cfg.acmeDnsCertMgr {
      acceptTerms = true;
      certs.routing = lib.mkIf (nodeName == "routing") {
        dnsProvider = "route53";
        dnsResolver = "1.1.1.1:53";
        email = "devops@iohk.io";
        inherit (config.cluster) domain;
        credentialsFile = builtins.toFile "nothing" "";
        extraDomainNames = [ "*.${domain}" ]
          ++ config.cluster.extraAcmeSANs;
        postRun = ''
          cp fullchain.pem ${letsencryptCertMaterial.certChainFile}
          cp key.pem ${letsencryptCertMaterial.keyFile}
          cp cert.pem ${letsencryptCertMaterial.certFile}
          systemctl try-restart --no-block traefik.service

          export VAULT_TOKEN="$(< ${hashiTokens.vault})"
          export VAULT_ADDR="https://core.vault.service.consul:8200"
          ${pkgs.vault}/bin/vault kv put kv/bootstrap/letsencrypt/key value=@key.pem
          ${pkgs.vault}/bin/vault kv put kv/bootstrap/letsencrypt/fullchain value=@fullchain.pem
          ${pkgs.vault}/bin/vault kv put kv/bootstrap/letsencrypt/cert value=@cert.pem
        '';
      };
    };

    services.traefik = {
      dynamicConfigOptions = let
        tlsCfg = if cfg.acmeDnsCertMgr then true else { certresolver = "acme"; };
      in {
        tls.certificates = if cfg.acmeDnsCertMgr then [{
          certFile = "/var/lib/traefik/certs/${builtins.baseNameOf letsencryptCertMaterial.certChainFile}";
          keyFile = "/var/lib/traefik/certs/${builtins.baseNameOf letsencryptCertMaterial.keyFile}";
        }] else [];

        http = {
          routers = let
            mkOauthRoute = service: {
              inherit service;
              entrypoints = "https";
              middlewares = [ "oauth-auth-redirect" ];
              rule = "Host(`${service}.${domain}`) && PathPrefix(`/`)";
              tls = tlsCfg;
            };
          in lib.mkDefault {
            oauth2-route = {
              entrypoints = "https";
              middlewares = [ "auth-headers" ];
              rule = "PathPrefix(`/oauth2/`)";
              service = "oauth-backend";
              priority = 999;
              tls = true;
            };

            oauth2-proxy-route = {
              entrypoints = "https";
              middlewares = [ "auth-headers" ];
              rule = "Host(`oauth.${domain}`) && PathPrefix(`/`)";
              service = "oauth-backend";
              tls = tlsCfg;
            };

            grafana = mkOauthRoute "monitoring";
            nomad = mkOauthRoute "nomad";

            nomad-api = {
              entrypoints = "https";
              middlewares = [ ];
              rule = "Host(`nomad.${domain}`) && PathPrefix(`/v1/`)";
              service = "nomad";
              tls = true;
            };

            vault = mkOauthRoute "vault";

            vault-api = {
              entrypoints = "https";
              middlewares = [ ];
              rule = "Host(`vault.${domain}`) && PathPrefix(`/v1/`)";
              service = "vault";
              tls = true;
            };

            consul = mkOauthRoute "consul";

            consul-api = {
              entrypoints = "https";
              middlewares = [ ];
              rule = "Host(`consul.${domain}`) && PathPrefix(`/v1/`)";
              service = "consul";
              tls = true;
            };

            traefik = {
              entrypoints = "https";
              middlewares = [ "oauth-auth-redirect" ];
              # middlewares = [ ];
              rule = "Host(`traefik.${domain}`) && PathPrefix(`/`)";
              service = "api@internal";
              tls = tlsCfg;
            };
          };

          services = {
            oauth-backend.loadBalancer = {
              servers = [{ url = "http://127.0.0.1:4180"; }];
            };

            consul.loadBalancer = {
              servers = [{ url = "http://127.0.0.1:8500"; }];
            };

            nomad.loadBalancer = {
              servers = [{ url = "https://nomad.service.consul:4646"; }];
              serversTransport = "cert-transport";
            };

            monitoring.loadBalancer = {
              servers = [{ url = "http://monitoring:3000"; }];
            };

            vault.loadBalancer = {
              servers = [{ url = "https://active.vault.service.consul:8200"; }];
              serversTransport = "cert-transport";
            };
          };

          serversTransports = {
            cert-transport = {
              insecureSkipVerify = true;
              rootCAs = let
                certChainFile = if deployType == "aws" then pkiFiles.certChainFile
                                                       else pkiFiles.serverCertChainFile;
              in [ certChainFile ];
            };
          };

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
                authResponseHeaders = [
                  "X-Auth-Request-Email"
                  "X-Auth-Request-Access-Token"
                  "Authorization"
                ];
                trustForwardHeader = true;
              };
            };
          };
        };
      };

      staticConfigOptions = {
        metrics = {
          prometheus = {
            entrypoint = "metrics";
            addEntryPointsLabels = true;
            addServicesLabels = true;
          };
        };

        accesslog = true;
        log.level = "info";

        api = { dashboard = true; };

        entryPoints = {
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

          metrics = {
            address =
              "127.0.0.1:${toString config.services.traefik.prometheusPort}";
          };
        };

        certificatesResolvers = if (!cfg.acmeDnsCertMgr) then {
          acme = {
            acme = {
              email = "devops@iohk.io";
              storage = "/var/lib/traefik/acme.json";
              httpChallenge = { entrypoint = "http"; };
            };
          };
        } else null;

        providers.consulCatalog = {
          refreshInterval = "30s";

          prefix = "traefik";

          # Forces the read to be fully consistent.
          requireConsistent = true;

          # Use stale consistency for catalog reads.
          stale = false;

          # Use local agent caching for catalog reads.
          cache = false;

          # Enable Consul Connect support.
          connectaware = true;

          # Consider every service as Connect capable by default.
          connectbydefault = false;

          endpoint = {
            # Defines the address of the Consul server.
            address = "127.0.0.1:${toString config.services.consul.ports.http}";

            scheme = "http";

            # Defines the datacenter to use. If not provided in Traefik, Consul uses the default agent datacenter.
            inherit datacenter;

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
  };
}
