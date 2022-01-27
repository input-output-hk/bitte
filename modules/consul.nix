{ config, lib, pkgs, bittelib, hashiTokens, gossipEncryptionMaterial, pkiFiles, ... }:
let
  cfg = config.services.consul;

  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;

  sanitize = obj:
    lib.getAttr (builtins.typeOf obj) {
      bool = obj;
      int = obj;
      string = obj;
      str = obj;
      list = map sanitize obj;
      path = toString obj;
      inherit null;
      set = if (builtins.length (builtins.attrNames obj) == 0) then
        null
      else
        lib.pipe obj [
          (lib.filterAttrs
            (name: value: name != "_module" && name != "_ref" && value != null))
          (lib.mapAttrs' (name: value:
            lib.nameValuePair (sanitizeName name) (sanitizeValue name value)))
        ];
    };

  # Some config cannot be snakeCase sanitized without breaking the functionality.
  # Example: consul service router, resolver and splitter configuration.
  excluded = [ "failover" "splits" "subsets" ];
  sanitizeName = name:
    if builtins.elem name excluded then name else bittelib.snakeCase name;
  sanitizeValue = name: value:
    if builtins.elem name excluded then value else sanitize value;

in {
  disabledModules = [ "services/networking/consul.nix" ];
  options = {
    services.consul = {
      enable = lib.mkEnableOption "Enable the consul daemon.";

      package = lib.mkOption {
        type = with lib.types; package;
        default = pkgs.consul;
      };

      configDir = lib.mkOption {
        type = with lib.types; str;
        default = "consul.d";
      };

      dataDir = lib.mkOption {
        type = with lib.types; path;
        default = /var/lib/consul;
      };

      ui = lib.mkEnableOption "Enable the web UI.";

      logLevel = lib.mkOption {
        type = with lib.types; enum [ "trace" "debug" "info" "warn" "err" ];
        default = "info";
      };

      serverNodeNames = lib.mkOption {
        type = with lib.types; listOf str;
        default = if deployType != "premSim" then [ "core-1" "core-2" "core-3" ]
                  else [ "prem-1" "prem-2" "prem-3" ];
      };

      extraConfig = lib.mkOption {
        type = with lib.types; attrs;
        default = { };
      };

      datacenter = lib.mkOption {
        type = with lib.types; str;
        default = "dc1";
        description = ''
          This flag controls the datacenter in which the agent is running. If
          not provided, it defaults to "dc1". Consul has first-class support
          for multiple datacenters, but it relies on proper configuration.
          Nodes in the same datacenter should be on a single LAN.
        '';
      };

      bootstrapExpect = lib.mkOption {
        type = with lib.types; nullOr ints.positive;
        default = null;
        description = ''
          This flag provides the number of expected servers in the datacenter.
          Either this value should not be provided or the value must agree with
          other servers in the cluster. When provided, Consul waits until the
          specified number of servers are available and then bootstraps the
          cluster. This allows an initial leader to be elected automatically.
        '';
      };

      enableScriptChecks = lib.mkEnableOption ''
        Enable script checks.
      '';

      enableLocalScriptChecks = lib.mkEnableOption ''
        Enable script checks defined in local config files. Script checks
        defined via the HTTP API will not be allowed.
      '';

      server = lib.mkEnableOption ''
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

      advertiseAddr = lib.mkOption {
        type = with lib.types; str;
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

      bindAddr = lib.mkOption {
        type = with lib.types; str;
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

      clientAddr = lib.mkOption {
        type = with lib.types; str;
        default = "127.0.0.1";
        description = ''
          The address to which Consul will bind client interfaces, including
          the HTTP and DNS servers. By default, this is "127.0.0.1", allowing
          only loopback connections. In Consul 1.0 and later this can be set to
          a space-separated list of addresses to bind to, or a go-sockaddr
          template that can potentially resolve to multiple addresses.
        '';
      };

      encrypt = lib.mkOption {
        type = with lib.types; nullOr str;
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

      addresses = lib.mkOption {
        type = with lib.types;
          submodule {
            options = { http = lib.mkOption { type = with lib.types; str; }; };
          };
        default = { };
      };

      retryJoin = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
      };

      primaryDatacenter = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
      };

      acl = lib.mkOption {
        default = { };
        type = with lib.types;
          nullOr (submodule {
            options = {
              enabled = lib.mkOption {
                type = with lib.types; nullOr bool;
                default = true;
              };

              defaultPolicy = lib.mkOption {
                type = with lib.types; nullOr (enum [ "deny" "allow" ]);
                default = "deny";
              };

              enableTokenPersistence = lib.mkOption {
                type = with lib.types; nullOr bool;
                default = true;
                description = ''
                  Enable token persistence for `consul acl set-agent-token`
                '';
              };

              downPolicy = lib.mkOption {
                type =
                  nullOr (enum [ "allow" "deny" "extend-cache" "async-cache" ]);
                default = "extend-cache";
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

      connect = lib.mkOption {
        type = with lib.types;
          submodule {
            options = {
              enabled = lib.mkEnableOption "Enable Consul Connect";

              caProvider = lib.mkOption {
                type = with lib.types; str;
                default = "consul";
              };

              caConfig = lib.mkOption {
                default = null;
                type = with lib.types;
                  nullOr (submodule {
                    options = {
                      address = lib.mkOption {
                        default = null;
                        type = with lib.types; nullOr str;
                      };

                      rootPkiPath = lib.mkOption {
                        default = null;
                        type = with lib.types; nullOr str;
                      };

                      intermediatePkiPath = lib.mkOption {
                        default = null;
                        type = with lib.types; nullOr str;
                      };

                      privateKey = lib.mkOption {
                        default = null;
                        type = with lib.types; nullOr str;
                      };

                      rootCert = lib.mkOption {
                        default = null;
                        type = with lib.types; nullOr str;
                      };
                    };
                  });
              };
            };
          };
        default = { };
      };

      caFile = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
      };

      certFile = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
      };

      keyFile = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
      };

      autoEncrypt = lib.mkOption {
        type = with lib.types;
          nullOr (submodule {
            options = {
              allowTls = lib.mkEnableOption "Allow TLS";
              tls = lib.mkEnableOption "Enable TLS";
            };
          });
        default = null;
      };

      verifyIncoming = lib.mkEnableOption "Verify incoming conns";

      verifyOutgoing = lib.mkEnableOption "Verify outgoing conns";

      verifyServerHostname = lib.mkEnableOption "Verify server hostname";

      ports = lib.mkOption {
        default = { };
        type = with lib.types;
          submodule {
            options = {
              grpc = lib.mkOption {
                type = with lib.types; nullOr port;
                default = null;
              };

              http = lib.mkOption {
                type = with lib.types; nullOr port;
                default = 8500;
              };

              https = lib.mkOption {
                type = with lib.types; nullOr port;
                default = null;
              };
            };
          };
      };

      tlsMinVersion = lib.mkOption {
        type = with lib.types; enum [ "tls10" "tls11" "tls12" "tls13" ];
        default = "tls12";
      };

      nodeMeta = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
      };

      telemetry = lib.mkOption {
        default = { };
        type = with lib.types;
          submodule {
            options = {
              dogstatsdAddr = lib.mkOption {
                type = with lib.types; nullOr str;
                default = null;
              };

              disableHostname = lib.mkOption {
                type = with lib.types; nullOr bool;
                default = null;
              };
            };
          };
      };

      nodeId = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
      };

      enableDebug = lib.mkOption {
        type = with lib.types; bool;
        default = false;
      };
    };
  };

  config = lib.mkIf cfg.enable {
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

      restartTriggers = lib.mapAttrsToList (_: d: d.source)
        (lib.filterAttrs (n: _: lib.hasPrefix "${cfg.configDir}/" n)
          config.environment.etc);

      path = with pkgs; [ envoy ];

      serviceConfig = let
        certChainFile = if deployType == "aws" then pkiFiles.certChainFile
                        else pkiFiles.serverCertChainFile;
        certKeyFile = if deployType == "aws" then pkiFiles.keyFile
                      else pkiFiles.serverKeyFile;
        preScript = let
          start-pre = pkgs.writeBashBinChecked "consul-start-pre" ''
            PATH="${lib.makeBinPath [ pkgs.coreutils ]}"
            set -exuo pipefail
            cp ${certChainFile} full.pem
            cp ${certKeyFile} cert-key.pem
            chown --reference . --recursive .
          '';
        in "!${start-pre}/bin/consul-start-pre";

        postScript = let
          start-post = pkgs.writeBashBinChecked "consul-start-post" ''
            set -exuo pipefail
            PATH="${lib.makeBinPath [ pkgs.jq cfg.package pkgs.coreutils ]}"
            set +x

            # During bootstrap the vault generated token are not yet available
            if [ -s ${hashiTokens.consul-default} ]
            then
              CONSUL_HTTP_TOKEN="$(< ${hashiTokens.consul-default})"
              export CONSUL_HTTP_TOKEN
            # Therefore, on core nodes, use the out-of-band bootstrapped master token
            elif [ -s ${gossipEncryptionMaterial.consul} ]
            then
              # as of writing: core nodes are observed to posess the master token
              # while clients do not
              jq -e .acl.tokens.master ${gossipEncryptionMaterial.consul} || exit 5
              CONSUL_HTTP_TOKEN="$(jq -e -r .acl.tokens.master ${gossipEncryptionMaterial.consul})"
              export CONSUL_HTTP_TOKEN
            else
              # Unknown state, should never reach this.
              exit 6
            fi

            set -x
            while ! consul info &>/dev/null; do sleep 3; done
          '';
        in "!${start-post}/bin/consul-start-post";

        reloadScript = let
          reload = pkgs.writeBashBinChecked "consul-reload" ''
            set -exuo pipefail
            PATH="${lib.makeBinPath [ pkgs.jq cfg.package pkgs.coreutils ]}"
            set +x

            # During bootstrap the vault generated token are not yet available
            if [ -s ${hashiTokens.consul-default} ]
            then
              CONSUL_HTTP_TOKEN="$(< ${hashiTokens.consul-default})"
              export CONSUL_HTTP_TOKEN
            # Therefore, on core nodes, use the out-of-band bootstrapped master token
            elif [ -s ${gossipEncryptionMaterial.consul} ]
            then
              # as of writing: core nodes are observed to posess the master token
              # while clients do not
              jq -e .acl.tokens.master ${gossipEncryptionMaterial.consul} || exit 5
              CONSUL_HTTP_TOKEN="$(jq -e -r .acl.tokens.master ${gossipEncryptionMaterial.consul})"
              export CONSUL_HTTP_TOKEN
            else
              # Unknown state, should never reach this.
              exit 6
            fi

            set -x
            cd /var/lib/consul/
            cp ${certChainFile} full.pem
            cp ${certKeyFile} cert-key.pem
            chown --reference . --recursive .
            consul reload
          '';
        in "!${reload}/bin/consul-reload";
      in {
        ExecStartPre = preScript;
        ExecReload = reloadScript;
        ExecStart =
          "@${cfg.package}/bin/consul consul agent -config-dir /etc/${cfg.configDir}";
        ExecStartPost = [ postScript ];
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
