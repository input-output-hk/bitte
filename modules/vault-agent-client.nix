{ config, lib, pkgs, ... }:
let
  inherit (builtins) toJSON isList;
  inherit (lib)
    mkIf filter mkEnableOption optional flip mapAttrsToList concatStringsSep;
  inherit (pkgs) writeShellScript;
  inherit (config.cluster) region domain;

  runIf = cond: value: if cond then value else null;
  compact = filter (value: value != null);

  pkiAttrs = {
    common_name = "server.${region}.consul";
    ip_sans = [ "127.0.0.1" ];
    alt_names =
      [ "vault.service.consul" "consul.service.consul" "nomad.service.consul" ];
    ttl = "322h";
  };

  pkiArgs = flip mapAttrsToList pkiAttrs (name: value:
    if isList value then
      ''"${name}=${concatStringsSep "," value}"''
    else
      ''"${name}=${toString value}"'');

  pkiSecret = ''"pki/issue/client" ${toString pkiArgs}'';

  vaultAgentConfig = pkgs.toPrettyJSON "vault-agent" {
    pid_file = "./vault-agent.pid";
    vault.address = "https://vault.${domain}:8200";

    # listener.unix = {
    #   address = "/run/vault/socket";
    #   tls_disable = true;
    # };

    # This requires at least one listener
    # but a listener defined without this would be silently ignored (https://github.com/hashicorp/vault/issues/8953)
    cache.use_auto_auth_token = true;
    listener = [{
      type = "tcp";
      address = "127.0.0.1:8200";
      tls_disable = true;
    }];

    auto_auth = {
      method = [{
        type = "aws";
        config = {
          type = "iam";
          role = "${config.cluster.name}-client";
          header_value = domain;
        };
      }];

      sinks = [{
        sink = {
          type = "file";
          config = { path = "/run/keys/vault-token"; };
          perms = "0644";
        };
      }];
    };

    templates = compact [
      {
        template = {
          destination = "/etc/ssl/certs/full.pem";

          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
            {{ range .Data.ca_chain }}{{ . }}
            {{ end }}{{ end }}
          '';

          command = "${pkgs.systemd}/bin/systemctl try-restart certs-updated.service";
        };
      }

      {
        template = {
          destination = "/etc/ssl/certs/cert.pem";

          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
            {{ range .Data.ca_chain }}{{ . }}
            {{ end }}{{ end }}
          '';
        };
      }

      {
        template = {
          destination = "/etc/ssl/certs/cert-key.pem";

          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.private_key }}{{ end }}
          '';
        };
      }

      (runIf config.services.consul.enable {
        template = {
          destination = "/etc/consul.d/tokens.json";

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

          command = "${pkgs.systemd}/bin/systemctl try-restart consul";
        };
      })

      (runIf config.services.consul.enable {
        template = {
          destination = "/run/keys/consul-default-token";

          contents = ''
            {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}
          '';

          command = "${pkgs.systemd}/bin/systemctl try-restart consul.service";
        };
      })

      (runIf config.services.vault.enable {
        template = {
          destination = "/etc/vault.d/consul-token.json";

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

          command = "${pkgs.systemd}/bin/systemctl try-reload-or-restart vault.service";
        };
      })

    ];
  };

in {
  options = {
    services.vault-agent-client.enable =
      mkEnableOption "Start vault-agent for clients";
  };

  config = mkIf config.services.vault-agent-client.enable {
    systemd.services.certs-updated = {
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

        systemctl try-restart consul.service

        if curl -s -k https://127.0.0.1:4646/v1/status/leader &> /dev/null; then
          systemctl try-restart nomad.service
        else
          systemctl start nomad.service
        fi

        touch /etc/ssl/certs/.last_restart
      '';
    };

    systemd.services.vault-agent = {
      before = (optional config.services.vault.enable "vault.service")
        ++ (optional config.services.consul.enable "consul.service")
        ++ (optional config.services.nomad.enable "nomad.service");
      wantedBy = [ "multi-user.target" ];

      environment = {
        inherit (config.environment.variables) AWS_DEFAULT_REGION;
        VAULT_FORMAT = "json";
        VAULT_ADDR = "https://vault.${domain}";
        CONSUL_HTTP_ADDR = "127.0.0.1:8500";
        VAULT_SKIP_VERIFY = "true";
      };

      path = with pkgs; [ vault-bin ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "30s";
        ExecStart =
          "${pkgs.vault-bin}/bin/vault agent -config ${vaultAgentConfig}";
      };
    };
  };
}
