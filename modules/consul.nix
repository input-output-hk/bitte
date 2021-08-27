{ config, lib, pkgs, ... }:
let
  cfg = config.services.consul;
  inherit (lib)
    mkIf pipe filterAttrs mapAttrs' nameValuePair flip concatMapStrings isList
    toLower mapAttrsToList hasPrefix mkEnableOption mkOption makeBinPath;
  inherit (lib.types)
    package str enum ints submodule listOf nullOr port path attrsOf attrs bool;
  inherit (builtins) toJSON length attrNames split typeOf;
  inherit (pkgs) snakeCase;

  sanitize = obj:
    lib.getAttr (typeOf obj) {
      bool = obj;
      int = obj;
      string = obj;
      str = obj;
      list = map sanitize obj;
      path = toString obj;
      null = null;
      set = if (length (attrNames obj) == 0) then
        null
      else
        pipe obj [
          (filterAttrs
            (name: value: name != "_module" && name != "_ref" && value != null))
          (mapAttrs'
            (name: value: nameValuePair (snakeCase name) (sanitize value)))
        ];
    };

in {
  options = {
    services.consul = {
      enable = mkEnableOption "Enable the consul daemon.";

      package = mkOption {
        type = package;
        default = pkgs.consul;
      };

      configDir = mkOption {
        type = str;
        default = "consul.d";
      };

      dataDir = mkOption {
        type = path;
        default = /var/lib/consul;
      };

      ui = mkEnableOption "Enable the web UI.";

      logLevel = mkOption {
        type = enum [ "trace" "debug" "info" "warn" "err" ];
        default = "info";
      };

      extraConfig = mkOption {
        type = attrs;
        default = { };
      };

      datacenter = mkOption {
        type = str;
        default = "dc1";
        description = ''
          This flag controls the datacenter in which the agent is running. If
          not provided, it defaults to "dc1". Consul has first-class support
          for multiple datacenters, but it relies on proper configuration.
          Nodes in the same datacenter should be on a single LAN.
        '';
      };

      bootstrapExpect = mkOption {
        type = nullOr ints.positive;
        default = null;
        description = ''
          This flag provides the number of expected servers in the datacenter.
          Either this value should not be provided or the value must agree with
          other servers in the cluster. When provided, Consul waits until the
          specified number of servers are available and then bootstraps the
          cluster. This allows an initial leader to be elected automatically.
        '';
      };

      enableScriptChecks = mkEnableOption ''
        Enable script checks.
      '';

      enableLocalScriptChecks = mkEnableOption ''
        Enable script checks defined in local config files. Script checks
        defined via the HTTP API will not be allowed.
      '';

      server = mkEnableOption ''
        This flag is used to control if an agent is in server or client mode.
        When provided, an agent will act as a Consul server. Each Consul
        cluster must have at least one server and ideally no more than 5 per
        datacenter. All servers participate in the Raft consensus algorithm to
        ensure that transactions occur in a consistent, linearizable manner.
        Transactions modify cluster state, which is maintained on all server
        nodes to ensure availability in the case of node failure. Server nodes
        also participate in a WAN gossip pool with server nodes in other
        datacenters. Servers act as gateways to other datacenters and forward
        traffic as appropriate.
      '';

      advertiseAddr = mkOption {
        type = str;
        default = "0.0.0.0";
        description = ''
          The address that should be bound to for internal cluster
          communications. This is an IP address that should be reachable by all
          other nodes in the cluster. By default, this is "0.0.0.0", meaning
          Consul will bind to all addresses on the local machine and will
          advertise the private IPv4 address to the rest of the cluster. If
          there are multiple private IPv4 addresses available, Consul will exit
          with an error at startup. If you specify "[::]", Consul will
          advertise the public IPv6 address. If there are multiple public IPv6
          addresses available, Consul will exit with an error at startup.
          Consul uses both TCP and UDP and the same port for both. If you have
          any firewalls, be sure to allow both protocols. In Consul 1.0 and
          later this can be set to a go-sockaddr template that needs to resolve
          to a single address. Some example templates:

          {{ GetPrivateInterfaces | include "network" "10.0.0.0/8" | attr "address" }}
          {{ GetInterfaceIP "eth0" }}
          {{ GetAllInterfaces | include "name" "^eth" | include "flags" "forwardable|up" | attr "address" }}
        '';
      };

      bindAddr = mkOption {
        type = str;
        default = "0.0.0.0";
        description = ''
          The address that should be bound to for internal cluster
          communications. This is an IP address that should be reachable by all
          other nodes in the cluster. By default, this is "0.0.0.0", meaning
          Consul will bind to all addresses on the local machine and will
          advertise the private IPv4 address to the rest of the cluster. If
          there are multiple private IPv4 addresses available, Consul will exit
          with an error at startup. If you specify "[::]", Consul will
          advertise the public IPv6 address. If there are multiple public IPv6
          addresses available, Consul will exit with an error at startup.
          Consul uses both TCP and UDP and the same port for both. If you have
          any firewalls, be sure to allow both protocols. In Consul 1.0 and
          later this can be set to a go-sockaddr template that needs to resolve
          to a single address. Some example templates:

          {{ GetPrivateInterfaces | include "network" "10.0.0.0/8" | attr "address" }}
          {{ GetInterfaceIP "eth0" }}
          {{ GetAllInterfaces | include "name" "^eth" | include "flags" "forwardable|up" | attr "address" }}
        '';
      };

      clientAddr = mkOption {
        type = str;
        default = "127.0.0.1";
        description = ''
          The address to which Consul will bind client interfaces, including
          the HTTP and DNS servers. By default, this is "127.0.0.1", allowing
          only loopback connections. In Consul 1.0 and later this can be set to
          a space-separated list of addresses to bind to, or a go-sockaddr
          template that can potentially resolve to multiple addresses.
        '';
      };

      encrypt = mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Specifies the secret key to use for encryption of Consul network
          traffic. This key must be 32-bytes that are Base64-encoded. The
          easiest way to create an encryption key is to use `consul keygen`.
          All nodes within a cluster must share the same encryption key to
          communicate. The provided key is automatically persisted to the data
          directory and loaded automatically whenever the agent is restarted.
          This means that to encrypt Consul's gossip protocol, this option only
          needs to be provided once on each agent's initial startup sequence.
          If it is provided after Consul has been initialized with an
          encryption key, then the provided key is ignored and a warning will
          be displayed.
        '';
      };

      addresses = mkOption {
        type = submodule { options = { http = mkOption { type = str; }; }; };
        default = { };
      };

      retryJoin = mkOption {
        type = listOf str;
        default = [ ];
      };

      primaryDatacenter = mkOption {
        type = nullOr str;
        default = null;
      };

      acl = mkOption {
        default = null;
        type = nullOr (submodule {
          options = {
            enabled = mkOption {
              type = nullOr bool;
              default = null;
            };

            defaultPolicy = mkOption {
              type = nullOr (enum [ "deny" "allow" ]);
              default = null;
            };

            enableTokenPersistence = mkOption {
              type = nullOr bool;
              default = null;
              description = ''
                Enable token persistence for `consul acl set-agent-token`
              '';
            };

            downPolicy = mkOption {
              type = nullOr (enum [
                "allow"
                "deny"
                "extend-cache"
                "async-cache"
                "extend-cache"
              ]);
              default = null;
              description = ''
                In the case that a policy or token cannot be read from the
                primary_datacenter or leader node, the down policy is applied.
                In "allow" mode, all actions are permitted, "deny" restricts
                all operations, and "extend-cache" allows any cached objects
                to be used, ignoring their TTL values. If a non-cached ACL is
                used, "extend-cache" acts like "deny". The value "async-cache"
                acts the same way as "extend-cache" but performs updates
                asynchronously when ACL is present but its TTL is expired,
                thus, if latency is bad between the primary and secondary
                datacenters, latency of operations is not impacted.
              '';
            };
          };
        });
      };

      connect = mkOption {
        type = submodule {
          options = {
            enabled = mkEnableOption "Enable Consul Connect";

            caProvider = mkOption {
              type = str;
              default = "consul";
            };

            caConfig = mkOption {
              default = null;
              type = nullOr (submodule {
                options = {
                  address = mkOption {
                    default = null;
                    type = nullOr str;
                  };

                  rootPkiPath = mkOption {
                    default = null;
                    type = nullOr str;
                  };

                  intermediatePkiPath = mkOption {
                    default = null;
                    type = nullOr str;
                  };

                  privateKey = mkOption {
                    default = null;
                    type = nullOr str;
                  };

                  rootCert = mkOption {
                    default = null;
                    type = nullOr str;
                  };
                };
              });
            };
          };
        };
        default = { };
      };

      caFile = mkOption {
        type = nullOr str;
        default = null;
      };

      certFile = mkOption {
        type = nullOr str;
        default = null;
      };

      keyFile = mkOption {
        type = nullOr str;
        default = null;
      };

      autoEncrypt = mkOption {
        type = nullOr (submodule {
          options = {
            allowTls = mkEnableOption "Allow TLS";
            tls = mkEnableOption "Enable TLS";
          };
        });
        default = null;
      };

      verifyIncoming = mkEnableOption "Verify incoming conns";

      verifyOutgoing = mkEnableOption "Verify outgoing conns";

      verifyServerHostname = mkEnableOption "Verify server hostname";

      ports = mkOption {
        default = { };
        type = submodule {
          options = {
            grpc = mkOption {
              type = nullOr port;
              default = null;
            };

            http = mkOption {
              type = nullOr port;
              default = 8500;
            };

            https = mkOption {
              type = nullOr port;
              default = null;
            };
          };
        };
      };

      tlsMinVersion = mkOption {
        type = enum [ "tls10" "tls11" "tls12" "tls13" ];
        default = "tls12";
      };

      nodeMeta = mkOption {
        type = attrsOf str;
        default = { };
      };

      telemetry = mkOption {
        default = { };
        type = submodule {
          options = {
            dogstatsdAddr = mkOption {
              type = nullOr str;
              default = null;
            };

            disableHostname = mkOption {
              type = nullOr bool;
              default = null;
            };
          };
        };
      };

      nodeId = mkOption {
        type = nullOr str;
        default = null;
      };

      enableDebug = mkOption {
        type = bool;
        default = false;
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    environment.variables = { CONSUL_HTTP_ADDR = "http://127.0.0.1:8500"; };

    environment.etc."${cfg.configDir}/config.json".source =
      pkgs.toPrettyJSON "config" (sanitize {
        inherit (cfg)
          ui datacenter bootstrapExpect bindAddr advertiseAddr server logLevel
          clientAddr encrypt addresses retryJoin primaryDatacenter acl connect
          caFile certFile keyFile autoEncrypt verifyServerHostname
          verifyOutgoing verifyIncoming dataDir tlsMinVersion ports
          enableLocalScriptChecks nodeMeta telemetry nodeId enableDebug
          enableScriptChecks;
      });

    environment.etc."${cfg.configDir}/extra-config.json".source =
      pkgs.toPrettyJSON "config" (sanitize cfg.extraConfig);

    systemd.services.consul = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      restartTriggers = mapAttrsToList (_: d: d.source)
        (filterAttrs (n: _: hasPrefix "${cfg.configDir}/" n)
          config.environment.etc);

      path = with pkgs; [ envoy ];

      serviceConfig = let
        preScript = let
          start-pre = pkgs.writeShellScriptBin "consul-start-pre" ''
            PATH="${makeBinPath [ pkgs.coreutils ]}"
            set -exuo pipefail
            cp /etc/ssl/certs/cert-key.pem .
            chown --reference . --recursive .
          '';
        in "!${start-pre}/bin/consul-start-pre";

        postScript = let
          start-post = pkgs.writeShellScriptBin "consul-start-post" ''
            set -exuo pipefail
            PATH="${makeBinPath [ pkgs.jq cfg.package pkgs.coreutils ]}"
            set +x
            CONSUL_HTTP_TOKEN="$(< /run/keys/consul-default-token)"
            export CONSUL_HTTP_TOKEN
            set -x
            while ! consul info &>/dev/null; do sleep 3; done
          '';
        in "!${start-post}/bin/consul-start-post";

        reloadScript = let
          reload = pkgs.writeShellScriptBin "consul-reload" ''
            set -exuo pipefail
            PATH="${makeBinPath [ pkgs.jq cfg.package pkgs.coreutils ]}"
            set +x
            CONSUL_HTTP_TOKEN="$(< /run/keys/consul-default-token)"
            export CONSUL_HTTP_TOKEN
            set -x
            cd /var/lib/consul/
            cp /etc/ssl/certs/cert-key.pem .
            chown --reference . --recursive .
            consul reload
          '';
        in "!${reload}/bin/consul-reload";
      in {
        ExecStartPre = preScript;
        ExecReload = reloadScript;
        ExecStart =
          "@${cfg.package}/bin/consul consul agent -config-dir /etc/${cfg.configDir}";
        ExecStartPost = postScript;
        Restart = "on-failure";
        RestartSec = "10s";
        DynamicUser = true;
        User = "consul";
        Group = "consul";
        PrivateTmp = true;
        StateDirectory = baseNameOf cfg.dataDir;
        WorkingDirectory = toString cfg.dataDir;
      };
    };
  };
}
