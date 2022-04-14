{ self, lib, pkgs, config, nodeName, bittelib, hashiTokens, letsencryptCertMaterial, pkiFiles, ... }:
let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
  datacenter = config.currentCoreNode.datacenter or config.cluster.region;
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
      default = lib.warn ''
        CAUTION: -- default will change soon to:
        services.traefik.acmeDnsCertMgr = false;
      '' true;
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

    useOauth2Proxy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Apply oauth middleware to the standard UI bitte services.
        One, but not both, of `useOauth2Proxy` or `useDigestAuth` options must be true.
      '';
    };

    useDigestAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Apply digest auth middleware to the standard UI bitte services.
        One, but not both, of `useOauth2Proxy` or `useDigestAuth` options must be true.
      '';
    };

    useDockerRegistry = lib.mkOption {
      type = lib.types.bool;
      default = lib.warn ''
        CAUTION: -- default will change soon to:
        services.traefik.useDockerRegistry = false;
      '' true;
      description = ''
        Enable use of a docker registry backend with a service hosted on the monitoring server.
      '';
    };

    useVaultBackend = lib.mkOption {
      type = lib.types.bool;
      default = lib.warn ''
        CAUTION: -- default will change soon to:
        services.traefik.useVaultBackend = true;
      '' false;
      description = ''
        Enable use of a vault TF backend with a service hosted on the monitoring server.
      '';
    };

    digestAuthFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/keys/digest-auth";
      description = ''
        The path to the digest-auth file for the `useDigestAuth` option.

        Format expected is:
          $USER:$REALM:$HASHED_PASSWORD

        Digest auth file ownership and perms are expected to be: root:keys 0640.
        Enabling this option will place the traefik user in the `key` group.

        Ref:
          https://doc.traefik.io/traefik/v2.0/middlewares/digestauth/
      '';
    };
  };

  config = {

    assertions = [
      {
        assertion = cfg.useOauth2Proxy != cfg.useDigestAuth;
        message = ''
          Both `useOauth2Proxy` and `useDigestAuth` options cannot be enabled at the same time.
          One of `useOauth2Proxy` and `useDigestAuth` options must be enabled.
        '';
      }
    ];

    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.consul.ui = true;
    services.traefik.enable = true;
    services.oauth2_proxy.enable = cfg.useOauth2Proxy;

    users.extraGroups.keys.members = lib.mkIf cfg.useDigestAuth [ "traefik" ];

    networking.extraHosts = ''
      ${config.cluster.nodes.monitoring.privateIP} monitoring
    '';

    # Only start traefik once the token is available
    systemd.paths.traefik-consul-token = {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        Unit = "traefik.service";
        PathExists = hashiTokens.traefik;
      };
    };

    # Get rid of the default `multi-user.target` so that the
    # above path unit actually has an effect.
    systemd.services.traefik.wantedBy = lib.mkForce [];

    systemd.services.traefik.serviceConfig.ExecStart = let
        cfg = config.services.traefik;
        jsonValue = with lib.types;
          let
            valueType = nullOr (oneOf [
              bool
              int
              float
              str
              (lazyAttrsOf valueType)
              (listOf valueType)
            ]) // {
              description = "JSON value";
              emptyValue.value = { };
            };
          in valueType;
        dynamicConfigFile = if cfg.dynamicConfigFile == null then
          pkgs.runCommand "config.toml" {
            buildInputs = [ pkgs.remarshal ];
            preferLocalBuild = true;
          } ''
            remarshal -if json -of toml \
              < ${
                pkgs.writeText "dynamic_config.json"
                (builtins.toJSON cfg.dynamicConfigOptions)
              } \
              > $out
          ''
        else
          cfg.dynamicConfigFile;
        staticConfigFile = if cfg.staticConfigFile == null then
          pkgs.runCommand "config.toml" {
            buildInputs = [ pkgs.yj ];
            preferLocalBuild = true;
          } ''
            yj -jt -i \
              < ${
                pkgs.writeText "static_config.json" (builtins.toJSON
                  (lib.recursiveUpdate cfg.staticConfigOptions {
                    providers.file.filename = "${dynamicConfigFile}";
                  }))
              } \
              > $out
          ''
        else
          cfg.staticConfigFile;
    in lib.mkForce (pkgs.writeShellScript "traefik.sh" ''
      export CONSUL_HTTP_TOKEN="$(< $CREDENTIALS_DIRECTORY/consul)"
      exec ${config.services.traefik.package}/bin/traefik --configfile=${staticConfigFile}
    '');
    systemd.services.traefik.serviceConfig.LoadCredential = "consul:${hashiTokens.traefik}";

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
        }] else [ ];

        http = {
          routers = let
            middlewares = lib.optional cfg.useOauth2Proxy "oauth-auth-redirect"
                          ++ lib.optional cfg.useDigestAuth "digest-auth";
            mkRoute = service: {
              inherit service middlewares;
              entrypoints = "https";
              rule = "Host(`${service}.${domain}`) && PathPrefix(`/`)";
              tls = tlsCfg;
            };
          in lib.mkDefault ({
            grafana = mkRoute "monitoring";
            nomad = mkRoute "nomad";

            nomad-api = {
              entrypoints = "https";
              middlewares = [ ];
              rule = "Host(`nomad.${domain}`) && PathPrefix(`/v1/`)";
              service = "nomad";
              tls = true;
            };

            vault = mkRoute "vault";

            vault-api = {
              entrypoints = "https";
              middlewares = [ ];
              rule = "Host(`vault.${domain}`) && PathPrefix(`/v1/`)";
              service = "vault";
              tls = true;
            };

            consul = mkRoute "consul";

            consul-api = {
              entrypoints = "https";
              middlewares = [ ];
              rule = "Host(`consul.${domain}`) && PathPrefix(`/v1/`)";
              service = "consul";
              tls = true;
            };

            traefik = {
              inherit middlewares;
              entrypoints = "https";
              rule = "Host(`traefik.${domain}`) && PathPrefix(`/`)";
              service = "api@internal";
              tls = tlsCfg;
            };
          } // (lib.optionalAttrs cfg.useDockerRegistry {
            docker-registry = {
              entrypoints = "https";
              middlewares = [ ];
              rule = "Host(`docker.${domain}`) && PathPrefix(`/`)";
              service = "docker-registry";
              tls = tlsCfg;
            };
          }) // (lib.optionalAttrs cfg.useOauth2Proxy {
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
          }) // (lib.optionalAttrs cfg.useVaultBackend {
            vault-backend = {
              entrypoints = "https";
              middlewares = [ ];
              rule = "Host(`vbk.${domain}`) && PathPrefix(`/`)";
              service = "vault-backend";
              tls = tlsCfg;
            };
          }));

          services = lib.mkDefault ({
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
          } // lib.optionalAttrs cfg.useDockerRegistry {
            docker-registry.loadBalancer = {
              servers = [{ url = "http://monitoring:5000"; }];
            };
          } // lib.optionalAttrs cfg.useOauth2Proxy {
            oauth-backend = {
              loadBalancer = {
                servers = [{ url = "http://127.0.0.1:4180"; }];
              };
            };
          } // lib.optionalAttrs cfg.useVaultBackend {
            vault-backend.loadBalancer = {
              servers = [{ url = "http://monitoring:8080"; }];
            };
          });

          serversTransports = {
            cert-transport = {
              insecureSkipVerify = true;
              rootCAs = let
                certChainFile = if deployType == "aws" then pkiFiles.certChainFile
                                                       else pkiFiles.serverCertChainFile;
              in [ certChainFile ];
            };
          };

          middlewares = lib.mkDefault ({
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
          } // lib.optionalAttrs cfg.useOauth2Proxy {
            oauth-auth-redirect = {
              forwardAuth = {
                address = "https://oauth.${domain}/";
                authResponseHeaders = [
                  "X-Auth-Request-User"
                  "X-Auth-Request-Email"
                  "X-Auth-Request-Access-Token"
                  "Authorization"
                ];
                trustForwardHeader = true;
              };
            };
          } // lib.optionalAttrs cfg.useDigestAuth {
            digest-auth = {
              digestAuth = {
                usersFile = cfg.digestAuthFile;
                removeHeader = true;
                headerField= "X-WebAuth-User";
              };
            };
          });
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
