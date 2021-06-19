{ config, lib, pkgs, ... }:
let
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

  pkiArgs = lib.flip lib.mapAttrsToList pkiAttrs (name: value:
    if builtins.isList value then
      ''"${name}=${lib.concatStringsSep "," value}"''
    else
      ''"${name}=${toString value}"'');

  pkiSecret = toString ([ ''"pki/issue/client"'' ] ++ pkiArgs);

  vaultAgentConfig = pkgs.toPrettyJSON "vault-agent" {
    pid_file = "/run/vault-agent.pid";

    vault = {
      address = config.services.vault-agent-client.vaultAddress;
      ca_cert = config.age.secrets.vault-ca.path;
      client_cert = config.age.secrets.vault-client.path;
      client_key = config.age.secrets.vault-client-key.path;
    };

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
        type = "cert";
        config = {
          name = "vault-agent-client";
          ca_cert = config.age.secrets.vault-ca.path;
          client_cert = config.age.secrets.vault-client.path;
          client_key = config.age.secrets.vault-client-key.path;
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

          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart certs-updated.service";
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

          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart certs-updated.service";
        };
      }

      {
        template = {
          destination = "/etc/ssl/certs/cert-key.pem";

          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.private_key }}{{ end }}
          '';

          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart certs-updated.service";
        };
      }

      (runIf config.services.consul.enable {
        template = {
          destination = "/etc/consul.d/tokens.json";

          contents = ''
            {
              "acl": {
                "default_policy": "deny",
                "down_policy": "extend-cache",
                "enable_token_persistence": true,
                "enabled": true,
                "tokens": {
                  "default": "{{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}",
                  "agent": "{{ with secret "consul/creds/consul-agent" }}{{ .Data.token }}{{ end }}"
                }
              }
            }
          '';

          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart consul";
        };
      })

      (runIf config.services.consul.enable {
        template = {
          destination = "/run/keys/consul-default-token";

          contents = ''
            {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}
          '';

          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart consul.service";
        };
      })

      (runIf config.services.vault.enable {
        template = {
          destination = "/etc/vault.d/consul-token.json";

          contents = ''
            {{ with secret "consul/creds/vault-client" }}
            {
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
      })

    ];
  };

in {
  options = {
    services.vault-agent-client = {
      enable = lib.mkEnableOption "Start vault-agent for clients";

      vaultAddress = lib.mkOption {
        type = lib.types.str;
        default = "https://vault.service.consul:8200";
      };
    };
  };

  config = lib.mkIf config.services.vault-agent-client.enable {
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

        systemctl try-reload-or-restart consul.service

        if curl -s -k https://127.0.0.1:4646/v1/status/leader &> /dev/null; then
          systemctl try-reload-or-restart nomad.service
        else
          systemctl start nomad.service
        fi
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
          "@${pkgs.vault-bin}/bin/vault vault-agent agent -config ${vaultAgentConfig}";
      };
    };
  };
}
