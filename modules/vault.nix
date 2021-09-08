{ lib, config, pkgs, nodeName, ... }:
let
  inherit (lib.types) attrs str bool enum submodule listOf ints nullOr;

  sanitize = obj:
    lib.getAttr (builtins.typeOf obj) {
      bool = obj;
      int = obj;
      string = obj;
      str = obj;
      list = map sanitize obj;
      null = null;
      set = if (builtins.length (builtins.attrNames obj) == 0) then
        null
      else
        lib.pipe obj [
          (lib.filterAttrs
            (name: value: name != "_module" && name != "_ref" && value != null))
          (lib.mapAttrs' (name: value:
            lib.nameValuePair (pkgs.snakeCase name) (sanitize value)))
        ];
    };

  storageRaftType = submodule {
    options = {
      path = lib.mkOption {
        type = str;
        default = cfg.storagePath;
      };

      nodeId = lib.mkOption {
        type = nullOr str;
        default = null;
      };

      retryJoin = lib.mkOption {
        type = listOf (submodule {
          options = {
            leaderApiAddr = lib.mkOption {
              type = str;
              description = ''
                Address of a possible leader node.
              '';
            };

            leaderCaCertFile = lib.mkOption {
              type = nullOr str;
              default = null;
              description = ''
                File path to the CA cert of the possible leader node.
              '';
            };

            leaderCaCert = lib.mkOption {
              type = nullOr str;
              default = null;
              description = ''
                CA cert of the possible leader node.
              '';
            };

            leaderClientCertFile = lib.mkOption {
              type = nullOr str;
              default = null;
              description = ''
                File path to the client certificate for the follower
                node to establish client authentication with the
                possible leader node.
              '';
            };

            leaderClientCert = lib.mkOption {
              type = nullOr str;
              default = null;
              description = ''
                Client certificate for the follower node to establish
                client authentication with the possible leader node.
              '';
            };

            leaderClientKeyFile = lib.mkOption {
              type = nullOr str;
              default = null;
              description = ''
                File path to the client key for the follower node to
                establish client authentication with the possible
                leader node.
              '';
            };

            leaderClientKey = lib.mkOption {
              type = nullOr str;
              default = null;
              description = ''
                Client key for the follower node to establish client
                authentication with the possible leader node.
              '';
            };
          };
        });
        default = [ ];
      };
    };
  };

  storageConsulType = submodule {
    options = {
      address = lib.mkOption {
        type = nullOr str;
        default = null;
      };

      scheme = lib.mkOption {
        type = nullOr (enum [ "http" "https" ]);
        default = null;
      };

      tlsCaFile = lib.mkOption {
        type = nullOr str;
        default = null;
      };

      tlsCertFile = lib.mkOption {
        type = nullOr str;
        default = null;
      };

      tlsKeyFile = lib.mkOption {
        type = nullOr str;
        default = null;
      };
    };
  };

  cfg = config.services.vault;
in {
  options.services.vault = {
    enable = lib.mkEnableOption "Vault daemon";

    storagePath = lib.mkOption {
      type = str;
      default = "/var/lib/vault";
    };

    configDir = lib.mkOption {
      type = str;
      default = "vault.d";
    };

    extraConfig = lib.mkOption {
      type = attrs;
      default = { };
    };

    ui = lib.mkEnableOption "Enable web UI";

    logLevel = lib.mkOption {
      type = enum [ "trace" "debug" "info" "warn" "err" ];
      default = "info";
    };

    disableMlock = lib.mkEnableOption "Disable mlock";

    apiAddr = lib.mkOption {
      type = nullOr str;
      default = null;
    };

    clusterAddr = lib.mkOption {
      type = nullOr str;
      default = null;
    };

    storage = lib.mkOption {
      default = null;
      type = nullOr (submodule {
        options = {
          raft = lib.mkOption {
            type = nullOr storageRaftType;
            default = null;
          };

          consul = lib.mkOption {
            type = nullOr storageConsulType;
            default = null;
          };
        };
      });
    };

    listener = lib.mkOption {
      type = submodule {
        options = {
          tcp = lib.mkOption {
            type = submodule {
              options = {
                address = lib.mkOption {
                  type = str;
                  default = "";
                };

                clusterAddress = lib.mkOption {
                  type = str;
                  default = "";
                };

                tlsClientCaFile = lib.mkOption {
                  type = str;
                  default = "";
                };

                tlsCertFile = lib.mkOption {
                  type = str;
                  default = "";
                };

                tlsKeyFile = lib.mkOption {
                  type = str;
                  default = "";
                };

                tlsMinVersion = lib.mkOption {
                  type = enum [ "tls10" "tls11" "tls12" "tls13" ];
                  default = "tls12";
                };
              };
            };
            default = { };
          };
        };
      };
      default = { };
    };

    seal = lib.mkOption {
      type = nullOr (submodule {
        options = {
          awskms = lib.mkOption {
            default = { };
            type = submodule {
              options = {
                kmsKeyId = lib.mkOption {
                  type = nullOr str;
                  default = null;
                };
                region = lib.mkOption {
                  type = nullOr str;
                  default = null;
                };
              };
            };
          };
        };
      });
      default = null;
    };

    serviceRegistration = lib.mkOption {
      type = nullOr (submodule {
        options = {
          consul = lib.mkOption {
            type = nullOr (submodule {
              options = {
                address = lib.mkOption {
                  type = nullOr str;
                  default = null;
                };

                scheme = lib.mkOption {
                  type = nullOr (enum [ "http" "https" ]);
                  default = null;
                };

                tlsClientCaFile = lib.mkOption {
                  type = nullOr str;
                  default = null;
                };

                tlsCertFile = lib.mkOption {
                  type = nullOr str;
                  default = null;
                };

                tlsKeyFile = lib.mkOption {
                  type = nullOr str;
                  default = null;
                };
              };
            });
            default = null;
          };
        };
      });
      default = null;
    };

    telemetry = lib.mkOption {
      type = submodule {
        options = {
          disableHostname = lib.mkOption {
            type = nullOr bool;
            default = null;
          };

          dogstatsdAddr = lib.mkOption {
            type = nullOr str;
            default = null;
          };

          dogstatsdTags = lib.mkOption {
            type = nullOr (listOf str);
            default = null;
          };
        };
      };
    };
  };

  disabledModules = [ "services/security/vault.nix" ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.vault-bin ];

    environment.etc."${cfg.configDir}/config.json".source =
      pkgs.toPrettyJSON "config" (sanitize {
        inherit (cfg)
          serviceRegistration ui logLevel disableMlock apiAddr clusterAddr seal
          listener storage telemetry;
      });

    environment.etc."${cfg.configDir}/extra-config.json".source =
      pkgs.toPrettyJSON "extra-config" cfg.extraConfig;

    systemd.services.vault = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      restartTriggers = lib.mapAttrsToList (_: d: d.source)
        (lib.filterAttrs (n: _: lib.hasPrefix "${cfg.configDir}" n)
          config.environment.etc);

      unitConfig = { RequiresMountsFor = [ cfg.storagePath ]; };

      startLimitBurst = 3;
      startLimitIntervalSec = 0;

      serviceConfig = let
        preScript = pkgs.writeShellScriptBin "vault-start-pre" ''
          export PATH="${lib.makeBinPath [ pkgs.coreutils ]}"
          set -exuo pipefail
          chown --reference . --recursive .
        '';

        postScript = pkgs.writeShellScriptBin "vault-start-post" ''
          export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.vault-bin ]}"
          while ! vault status; do sleep 3; done
        '';
      in {
        ExecStartPre = "!${preScript}/bin/vault-start-pre";
        ExecStart =
          "@${pkgs.vault-bin}/bin/vault vault server -config /etc/${cfg.configDir}";

        # ExecStartPost = "!${postScript}/bin/vault-start-post";
        KillSignal = "SIGINT";

        StateDirectory = baseNameOf cfg.storagePath;
        WorkingDirectory = cfg.storagePath;

        DynamicUser = true;
        User = "vault";
        Group = "vault";

        LimitMEMLOCK = "infinity";
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectSystem = "full";
        ProtectHome = "read-only";
        AmbientCapabilities = "cap_ipc_lock";
        NoNewPrivileges = true;

        TimeoutStopSec = "30s";
        RestartSec = "10s";
        Restart = "on-failure";
      };
    };
  };
}
