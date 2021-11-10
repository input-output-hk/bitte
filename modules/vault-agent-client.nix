{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkEnableOption flip mapAttrsToList concatStringsSep;
  inherit (pkgs) writeShellScript;
  inherit (config.cluster) region domain;

  cfg = config.services.vault-agent-client;

  consulAgentToken = if cfg.disableTokenRotation.consulAgent then
    ''
      {{ with secret "kv/bootstrap/static-tokens/clients/consul-agent" }}{{ .Data.data.token }}{{ end }}''
  else
    ''{{ with secret "consul/creds/consul-agent" }}{{ .Data.token }}{{ end }}'';

  consulDefaultToken = if cfg.disableTokenRotation.consulDefault then
    ''
      {{ with secret "kv/bootstrap/static-tokens/clients/consul-default" }}{{ .Data.data.token }}{{ end }}''
  else
    ''
      {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}'';

  pkiAttrs = {
    common_name = "server.${region}.consul";
    ip_sans = [ "127.0.0.1" ];
    alt_names =
      [ "vault.service.consul" "consul.service.consul" "nomad.service.consul" ];
    ttl = "322h";
  };

  pkiArgs = flip mapAttrsToList pkiAttrs (name: value:
    if builtins.isList value then
      ''"${name}=${concatStringsSep "," value}"''
    else
      ''"${name}=${toString value}"'');

  pkiSecret = ''"pki/issue/client" ${toString pkiArgs}'';
in {
  options = {
    services.vault-agent-client = {
      enable = mkEnableOption "Start vault-agent for clients";
      disableTokenRotation = lib.mkOption {
        default = { };
        type = lib.types.submodule {
          options = {
            consulAgent = lib.mkEnableOption
              "Disable consul agent token rotation on vault-agent-client nodes";
            consulDefault = lib.mkEnableOption
              "Disable consul default token rotation on vault-agent-client nodes";
          };
        };
      };
    };
  };

  config = mkIf config.services.vault-agent-client.enable {
    environment.variables.VAULT_ADDR = "http://127.0.0.1:8200";
    services.vault-agent = {
      enable = true;
      role = "client";
      vaultAddress = "https://vault.${domain}";

      cache.useAutoAuthToken = true;

      autoAuthMethod = "aws";

      autoAuthConfig = {
        type = "iam";
        role = "${config.cluster.name}-client";
        header_value = domain;
      };

      listener = [
        {
          type = "tcp";
          address = "127.0.0.1:8200";
          tlsDisable = true;
        }
        {
          type = "tcp";
          address = "172.17.0.1:8200";
          tlsDisable = true;
        }
      ];

      templates = {
        "/etc/ssl/certs/full.pem" = {
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
            {{ range .Data.ca_chain }}{{ . }}
            {{ end }}{{ end }}
          '';

          command =
            "${pkgs.systemd}/bin/systemctl try-restart certs-updated.service";
        };

        "/etc/ssl/certs/cert.pem" = {
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
            {{ range .Data.ca_chain }}{{ . }}
            {{ end }}{{ end }}
          '';

          command =
            "${pkgs.systemd}/bin/systemctl try-restart certs-updated.service";
        };

        "/etc/ssl/certs/cert-key.pem" = {
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.private_key }}{{ end }}
          '';

          command =
            "${pkgs.systemd}/bin/systemctl try-restart certs-updated.service";
        };

        "/etc/consul.d/tokens.json" = mkIf config.services.consul.enable {
          contents = ''
            {
              "encrypt": "{{ with secret "kv/bootstrap/clients/consul" }}{{ .Data.data.encrypt }}{{ end }}",
              "acl": {
                "tokens": {
                  "agent": "${consulAgentToken}",
                  "default": "${consulDefaultToken}"
                }
              }
            }
          '';

          command = "${pkgs.systemd}/bin/systemctl try-restart consul";
        };

        "/run/keys/consul-default-token" = mkIf config.services.consul.enable {
          contents = ''
            ${consulDefaultToken}
          '';

          command = "${pkgs.systemd}/bin/systemctl try-restart consul.service";
        };

        "/run/keys/nomad-consul-token" = mkIf config.services.nomad.enable {
          contents = ''
            ${consulDefaultToken}
          '';

          command = "${pkgs.systemd}/bin/systemctl try-restart nomad.service";
        };

        "/etc/vault.d/consul-token.json" = mkIf config.services.vault.enable {
          contents = ''
            {{ with secret "consul/creds/vault-client" }}
            {
              "storage": {
                "consul": {
                  "token": "{{ .Data.token }}",
                  "address": "127.0.0.1:8500",
                  "tlsCaFile": "/etc/ssl/certs/full.pem",
                  "tlsCertFile": "/etc/ssl/certs/cert.pem",
                  "tlsKeyFile": "/var/lib/vault/cert-key.pem"
                }
              },
              "service_registration": {
                "consul": {
                  "token": "{{ .Data.token }}",
                  "address": "127.0.0.1:8500",
                }
              }
            }
            {{ end }}
          '';

          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart vault.service";
        };
      };
    };

    systemd.services.certs-updated = {
      wantedBy = [ "multi-user.target" ];
      after = [ "vault-agent.service" ];
      path = with pkgs; [ coreutils curl systemd ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
      };

      script = ''
        set -exuo pipefail

        test -f /etc/ssl/certs/.last_restart || touch -d '2020-01-01' /etc/ssl/certs/.last_restart
        [ /etc/ssl/certs/full.pem -nt /etc/ssl/certs/.last_restart ]
        [ /etc/ssl/certs/cert.pem -nt /etc/ssl/certs/.last_restart ]
        [ /etc/ssl/certs/cert-key.pem -nt /etc/ssl/certs/.last_restart ]

        systemctl try-reload-or-restart consul.service

        if curl -s -k https://127.0.0.1:4646/v1/status/leader &> /dev/null; then
          systemctl try-reload-or-restart nomad.service
        else
          systemctl start nomad.service
        fi

        touch /etc/ssl/certs/.last_restart
      '';
    };
  };
}
