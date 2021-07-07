{ config, lib, pkgs, ... }:
let
  inherit (lib)
    mkIf mkEnableOption flip mapAttrsToList concatStringsSep;
  inherit (pkgs) writeShellScript;
  inherit (config.cluster) region domain;

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
    services.vault-agent-client.enable =
      mkEnableOption "Start vault-agent for clients";
  };

  config = mkIf config.services.vault-agent-client.enable {
    services.vault-agent = {
      enable = true;
      role = "client";
      vaultAddress = "https://vault.${domain}:8200";
      autoAuthMethod = "aws";
      autoAuthConfig = {
        type = "iam";
        role = "${config.cluster.name}-client";
        header_value = domain;
      };

      templates = {
        "/etc/ssl/certs/full.pem" = {
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
            {{ range .Data.ca_chain }}{{ . }}
            {{ end }}{{ end }}
          '';

          command = "${pkgs.systemd}/bin/systemctl restart certs-updated.service";
        };
        "/etc/ssl/certs/cert.pem" = {
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
            {{ range .Data.ca_chain }}{{ . }}
            {{ end }}{{ end }}
          '';

          command = "${pkgs.systemd}/bin/systemctl restart certs-updated.service";
        };

        "/etc/ssl/certs/cert-key.pem" = {
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.private_key }}{{ end }}
          '';

          command = "${pkgs.systemd}/bin/systemctl restart certs-updated.service";
        };

        "/etc/consul.d/tokens.json" = mkIf config.services.consul.enable {
          contents = ''
            {
              "encrypt": "{{ with secret "kv/bootstrap/clients/consul" }}{{ .Data.data.encrypt }}{{ end }}",
              "acl": {
                "default_policy": "${config.services.consul.acl.defaultPolicy}",
                "down_policy": "${config.services.consul.acl.downPolicy}",
                "enable_token_persistence": true,
                "enabled": true,
                "tokens": {
                  "default": "{{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}",
                  "agent": "{{ with secret "consul/creds/consul-agent" }}{{ .Data.token }}{{ end }}"
                }
              }
            }
          '';

          command = "${pkgs.systemd}/bin/systemctl reload consul";
        };

        "/run/keys/consul-default-token" = mkIf config.services.consul.enable {
          contents = ''
            {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}
          '';

          command = "${pkgs.systemd}/bin/systemctl reload consul.service";
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

          command = "${pkgs.systemd}/bin/systemctl restart vault.service";
        };
      };
    };

    systemd.services.certs-updated = {
      path = with pkgs; [ coreutils curl systemd ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
        ExecStartPre = writeShellScript "wait-for-certs" ''
          set -exuo pipefail

             test -f /etc/ssl/certs/full.pem \
          && test -f /etc/ssl/certs/cert.pem \
          && test -f /etc/ssl/certs/cert-key.pem
        '';
      };

      script = ''
        set -xu

        # this service will be invoked 3 times in short succession, so we try
        # to run this only once per certificate change to keep restarts to a
        # minimum
        sleep 10

        systemctl reload consul.service

        systemctl restart vault.service

        if curl -s -k https://127.0.0.1:4646/v1/status/leader &> /dev/null; then
          systemctl restart nomad.service
        else
          systemctl start nomad.service
        fi
      '';
    };
  };
}
