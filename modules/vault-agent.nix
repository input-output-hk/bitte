{ config, pkgs, lib, ... }:
let
  cfg = config.services.vault-agent;
  inherit (lib) types mkIf mkOption mkEnableOption;

  templateType = types.submodule ({ name, ... }: {
    options = {
      destination = lib.mkOption {
        type = types.str;
        default = name;
      };
      contents = lib.mkOption { type = types.str; };
      command = lib.mkOption { type = types.str; };
    };
  });
in {
  options.services.vault-agent = {
    enable = mkEnableOption "Enable the vault-agent";

    role = mkOption { type = types.enum [ "client" "core" ]; };

    vaultAddress = mkOption {
      type = types.str;
      default = "https://active.vault.service.consul:8200";
    };

    autoAuthMethod = mkOption {
      type = types.enum [ "aws" "cert" ];
      default = "aws";
    };

    autoAuthConfig = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };

    templates = lib.mkOption { type = types.attrsOf templateType; };
  };

  config = mkIf cfg.enable {
    systemd.services.vault-agent = let
      configFile = pkgs.toPrettyJSON "vault-agent" {
        pid_file = "/run/vault-agent.pid";
        vault.address = cfg.vaultAddress;

        auto_auth = {
          method = [{
            type = cfg.autoAuthMethod;
            config = cfg.autoAuthConfig;
          }];

          sinks = [{
            sink = {
              type = "file";
              config = { path = "/run/keys/vault-token"; };
              perms = "0644";
            };
          }];
        };

        templates = cfg.templates;
      };
    in {
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
        inherit (config.environment.variables) AWS_DEFAULT_REGION;
        CONSUL_HTTP_ADDR = "127.0.0.1:8500";
        VAULT_ADDR = cfg.vaultAddress;
        VAULT_SKIP_VERIFY = "true";
        VAULT_FORMAT = "json";
      };

      path = with pkgs; [ vault-bin ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "30s";
        ExecStart = "${pkgs.vault-bin}/bin/vault agent -config ${configFile}";
      };
    };
  };
}
