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

      templates = {
        "/etc/consul.d/tokens.json" = mkIf config.services.consul.enable {
          command = "${pkgs.systemd}/bin/systemctl reload consul.service";
          contents =
            if (nodeName == "monitoring" || nodeName == "hydra") then ''
              {
                "acl": {
                  "default_policy": "${config.services.consul.acl.defaultPolicy}",
                  "down_policy": "${config.services.consul.acl.downPolicy}",
                  "enable_token_persistence": true,
                  "enabled": true,
                  "tokens": {
                    "agent": "{{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}"
                  }
                }
              }
            '' else ''
              {
                "acl": {
                  "default_policy": "${config.services.consul.acl.defaultPolicy}",
                  "down_policy": "${config.services.consul.acl.downPolicy}",
                  "enable_token_persistence": true,
                  "enabled": true,
                  "tokens": {
                    "default": "{{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}",
                    "agent": "{{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}"
                  }
                }
              }
            '';
        };

        "/run/keys/consul-default-token" = mkIf config.services.consul.enable {
          command = "${pkgs.systemd}/bin/systemctl reload consul.service";
          contents = ''
            {{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}
          '';
        };

        # TODO: remove duplication
        "/etc/nomad.d/consul-token.json" = mkIf config.services.nomad.enable {
          command = "${pkgs.systemd}/bin/systemctl restart nomad.service";
          contents = ''
            {
              "consul": {
                "token": "{{ with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end }}"
              }
            }
          '';
        };

        "/run/keys/nomad-consul-token" = mkIf config.services.nomad.enable {
          command = "${pkgs.systemd}/bin/systemctl restart nomad.service";
          contents = ''
            {{- with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end -}}
          '';
        };

        "/run/keys/nomad-autoscaler-token" =
          mkIf config.services.nomad-autoscaler.enable {
            command =
              "${pkgs.systemd}/bin/systemctl restart nomad-autoscaler.service";
            contents = ''
              {{- with secret "nomad/creds/nomad-autoscaler" }}{{ .Data.secret_id }}{{ end -}}
            '';
          };
      };
    };
  };
}
