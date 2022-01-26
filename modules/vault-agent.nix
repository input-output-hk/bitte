{ config, pkgs, lib, ... }:
let
  cfg = config.services.vault-agent;

  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;

  templateType = with lib.types;
    submodule ({ name, ... }: {
      options = {
        destination = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };
        contents = lib.mkOption { type = with lib.types; str; };
        command = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
        };
      };
    });

  listenerType = with lib.types;
    submodule {
      options = {
        type = lib.mkOption { type = with lib.types; str; };
        address = lib.mkOption { type = with lib.types; str; };
        tlsDisable = lib.mkOption { type = with lib.types; bool; };
      };
    };

in {
  imports = [
    (lib.mkRenamedOptionModule [ "services" "vault-agent-core" "disableTokenRotation" "consulAgent" ] [ "services" "vault-agent" "disableTokenRotation" "consulAgent" ])
    (lib.mkRenamedOptionModule [ "services" "vault-agent-core" "disableTokenRotation" "consulDefault" ] [ "services" "vault-agent" "disableTokenRotation" "consulDefault" ])
    (lib.mkRenamedOptionModule [ "services" "vault-agent-client" "disableTokenRotation" "consulAgent" ] [ "services" "vault-agent" "disableTokenRotation" "consulAgent" ])
    (lib.mkRenamedOptionModule [ "services" "vault-agent-client" "disableTokenRotation" "consulDefault" ] [ "services" "vault-agent" "disableTokenRotation" "consulDefault" ])
  ];
  options.services.vault-agent = {
    enable = lib.mkEnableOption "Enable the vault-agent";

    disableTokenRotation = lib.mkOption {
      default = { };
      type = with lib.types;
        submodule {
          options = {
            consulAgent = lib.mkEnableOption
              "Disable consul agent token rotation on vault-agent-core nodes";
            consulDefault = lib.mkEnableOption
              "Disable consul default token rotation on vault-agent-core nodes";
          };
        };
    };

    role = lib.mkOption { type = with lib.types; enum [ "client" "core" "routing" ]; };

    vaultAddress = lib.mkOption {
      type = with lib.types; str;
      default = "https://active.vault.service.consul:8200";
    };

    autoAuthMethod = lib.mkOption {
      type = with lib.types; enum [ "aws" "cert" ];
      default = if deployType == "aws" then "aws" else "cert";
    };

    autoAuthConfig = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = { };
    };

    cache = lib.mkOption {
      default = { };
      type = with lib.types;
        submodule {
          options = {
            useAutoAuthToken = lib.mkOption {
              type = with lib.types; bool;
              default = true;
            };
          };
        };
    };

    listener = lib.mkOption {
      type = with lib.types; listOf listenerType;
      default = [ ];
    };

    sinks = lib.mkOption {
      type = with lib.types; listOf attrs;
      default = [ ];
    };

    templates = lib.mkOption { type = with lib.types; attrsOf templateType; };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.vault-agent = let
      configFile = pkgs.toPrettyJSON "vault-agent" ({
        pid_file = "/run/vault-agent.pid";
        vault.address = cfg.vaultAddress;

        auto_auth = {
          method = [{
            type = cfg.autoAuthMethod;
            config = cfg.autoAuthConfig;
          }];
          inherit (cfg) sinks;
        };

        templates = lib.mapAttrs (name: value:
          {
            inherit (value) destination contents;
          } // (lib.optionalAttrs (value.command != null) {
            inherit (value) command;
          })) cfg.templates;
      } // (lib.optionalAttrs (builtins.length cfg.listener > 0) {
        cache.use_auto_auth_token = cfg.cache.useAutoAuthToken;

        listener = lib.forEach cfg.listener (l: {
          inherit (l) type;
          inherit (l) address;
          tls_disable = l.tlsDisable;
        });
      }));
    in {
      description = "Obtain secrets from Vault";
      before = lib.mkIf (cfg.role == "core")
        ((lib.optional config.services.vault.enable "vault.service")
          ++ (lib.optional config.services.consul.enable "consul.service")
          ++ (lib.optional config.services.nomad.enable "nomad.service"));
      after =
        lib.mkIf (cfg.role == "client") [ "vault.service" "consul.service" ];
      wants =
        lib.mkIf (cfg.role == "client") [ "vault.service" "consul.service" ];

      wantedBy = [ "multi-user.target" ];

      environment = {
        CONSUL_HTTP_ADDR = "127.0.0.1:8500";
        VAULT_ADDR = cfg.vaultAddress;
        VAULT_SKIP_VERIFY = "true";
        VAULT_FORMAT = "json";
      } // (lib.optionalAttrs (config.environment.variables ? "AWS_DEFAULT_REGION") {
        inherit (config.environment.variables) AWS_DEFAULT_REGION;
      });

      path = with pkgs; [ vault-bin ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "30s";
        ExecStart = "${pkgs.vault-bin}/bin/vault agent -config ${configFile}";
        LimitNOFILE = "infinity";
      };
    };
  };
}
