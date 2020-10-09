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

  reload-cvn = writeShellScript "reload-cvn" ''
    set -x

    export PATH="$PATH:${
      lib.makeBinPath (with pkgs; [ coreutils systemd curl ])
    }"

    rm -f /etc/nomad.d/consul-token.json

    systemctl reload consul.service || true

    if curl -s -k https://127.0.0.1:4646/v1/status/leader &> /dev/null; then
      systemctl restart nomad.service || true
    else
      systemctl start nomad.service || true
    fi

    systemctl restart vault.service || true
    exit 0
  '';

  vaultAgentConfig = pkgs.toPrettyJSON "vault-agent" {
    pid_file = "./vault-agent.pid";
    vault.address = "https://vault.${domain}:8200";
    # exit_after_auth = true;
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
          command = reload-cvn;
          destination = "/etc/ssl/certs/full.pem";
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
            {{ range .Data.ca_chain }}{{ . }}
            {{ end }}{{ end }}
          '';
        };
      }

      {
        template = {
          command = reload-cvn;
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
          command = reload-cvn;
          destination = "/etc/ssl/certs/cert-key.pem";
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.private_key }}{{ end }}
          '';
        };
      }

      (runIf config.services.consul.enable {
        template = {
          destination = "/etc/consul.d/tokens.json";
          command = reload-cvn;
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
        };
      })

      (runIf config.services.nomad.enable {
        template = {
          command = reload-cvn;
          destination = "/run/keys/nomad-consul-token";
          contents = ''
            {{ with secret "consul/creds/nomad-client" }}{{ .Data.token }}{{ end }}
          '';
        };
      })

      (runIf config.services.vault.enable {
        template = {
          command = reload-cvn;
          destination = "/etc/vault.d/consul-token.json";
          contents = ''
            {{ with secret "consul/creds/vault-client" }}
            {
              "storage": {
                "consul": {
                  "token": "{{ .Data.token }}",
                  "address": "127.0.0.1:8500",
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
    systemd.services.vault-agent = {
      before = (optional config.services.vault.enable "vault.service")
        ++ (optional config.services.consul.enable "consul.service")
        ++ (optional config.services.nomad.enable "nomad.service");
      wantedBy = [ "multi-user.target" ];

      environment = {
        inherit (config.environment.variables) AWS_DEFAULT_REGION VAULT_FORMAT;
        VAULT_ADDR = "https://vault.${domain}";
        # VAULT_CACERT = "/etc/ssl/certs/full.pem";
        CONSUL_HTTP_ADDR = "127.0.0.1:8500";
        # CONSUL_CACERT = "/etc/ssl/certs/full.pem";
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
