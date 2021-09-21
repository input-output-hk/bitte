{ config, lib, pkgs, nodeName, ... }:
let
  inherit (builtins) isList;
  inherit (lib) mkIf filter mkEnableOption concatStringsSep flip mapAttrsToList;
  inherit (config.cluster) domain region;
  inherit (config.cluster.instances.${nodeName}) privateIP;
in {
  options = {
    services.vault-agent-core = {
      enable = mkEnableOption "Start vault-agent for cores";
      vaultAddress = lib.mkOption {
        type = lib.types.str;
        default = "https://127.0.0.1:8200";
      };
    };
  };

  config = mkIf config.services.vault-agent-core.enable {
    services.vault-agent = {
      enable = true;
      role = "core";
      vaultAddress = config.services.vault-agent-core.vaultAddress;
      autoAuthMethod = "aws";

      autoAuthConfig = {
        type = "iam";
        role = "${config.cluster.name}-core";
        header_value = domain;
      };

      templates = let
        reload = pkgs.writeShellScript "reload.sh" ''
          ${pkgs.systemd}/bin/systemctl --no-block try-reload-or-restart $1 || true
        '';

        restart = pkgs.writeShellScript "reload.sh" ''
          ${pkgs.systemd}/bin/systemctl --no-block try-restart $1 || true
        '';
      in {
        "/etc/consul.d/tokens.json" = mkIf config.services.consul.enable {
          command = "${reload} consul.service";
          contents = ''
            {
              "acl": {
                "default_policy": "deny",
                "down_policy": "extend-cache",
                "enable_token_persistence": true,
                "enabled": true,
                "tokens": {
                  "agent": "{{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}",
                  "default": "{{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}"
                }
              }
            }
          '';
        };

        "/run/keys/consul-default-token" = mkIf config.services.consul.enable {
          command = "${reload} consul.service";
          contents = ''
            {{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}
          '';
        };

        # TODO: remove duplication
        "/etc/nomad.d/consul-token.json" = mkIf config.services.nomad.enable {
          command = "${restart} nomad.service";
          contents = ''
            {
              "consul": {
                "token": "{{ with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end }}"
              }
            }
          '';
        };

        "/run/keys/nomad-consul-token" = mkIf config.services.nomad.enable {
          command = "${restart} nomad.service";
          contents = ''
            {{- with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end -}}
          '';
        };

        "/run/keys/nomad-autoscaler-token" =
          mkIf config.services.nomad-autoscaler.enable {
            command = "${reload} nomad-autoscaler.service";
            contents = ''
              {{- with secret "nomad/creds/nomad-autoscaler" }}{{ .Data.secret_id }}{{ end -}}
            '';
          };

        "/run/keys/nomad-snapshot-token" =
          mkIf config.services.nomad-snapshot.enable {
            contents = ''
              {{- with secret "nomad/creds/management" }}{{ .Data.secret_id }}{{ end -}}
            '';
          };
      };
    };
  };
}
