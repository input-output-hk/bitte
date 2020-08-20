{ config, lib, pkgs, ... }:
let
  inherit (builtins) toJSON isList;
  inherit (lib)
    mkIf filter mkEnableOption optional flip mapAttrsToList concatStringsSep;
  inherit (pkgs) writeShellScriptBin;
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

  reload-cvn = writeShellScriptBin "reload-cvn" ''
    set -x
    ${pkgs.systemd}/bin/systemctl reload consul.service
    ${pkgs.systemd}/bin/systemctl restart nomad.service
    ${pkgs.systemd}/bin/systemctl reload vault.service
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
      (runIf config.services.consul.enable {
        template = {
          destination = "/etc/consul.d/tokens.json";
          command = "${pkgs.systemd}/bin/systemctl reload consul.service";
          contents = ''
            {
              "encrypt": "{{ with secret "kv/bootstrap/clients/consul" }}{{ .Data.data.encrypt }}{{ end }}",
              "acl": {
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
          command = "${pkgs.systemd}/bin/systemctl restart nomad.service";
          destination = "/etc/nomad.d/consul-token.json";
          contents = ''
            {{ with secret "consul/creds/nomad-client" }}
            {
              "consul": {
                "token": "{{ .Data.token }}"
              }
            }
            {{ end }}
          '';
        };
      })

      (runIf config.services.vault.enable {
        template = {
          command = "${pkgs.systemd}/bin/systemctl reload vault.service";
          destination = "/etc/vault.d/consul-token.json";
          contents = ''
            {{ with secret "consul/creds/vault-client" }}
            {
              "storage": {
                "consul": {
                  "token": "{{ .Data.token }}"
                }
              },
              "service_registration": {
                "consul": {
                  "token": "{{ .Data.token }}"
                }
              }
            }
            {{ end }}
          '';
        };
      })

      {
        template = {
          command = "${reload-cvn}/bin/reload-cvn";
          destination = "/etc/ssl/certs/full.pem";
          contents = ''
            {{ with secret ${pkiSecret} }}{{ range .Data.ca_chain }}{{ . }}{{ end }}
            {{ .Data.certificate }}{{ end }}
          '';
        };
      }

      {
        template = {
          command = "${reload-cvn}/bin/reload-cvn";
          destination = "/etc/ssl/certs/cert.pem";
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.certificate }}{{ end }}
          '';
        };
      }

      {
        template = {
          command = "${reload-cvn}/bin/reload-cvn";
          destination = "/etc/ssl/certs/cert-key.pem";
          contents = ''
            {{ with secret ${pkiSecret} }}{{ .Data.private_key }}{{ end }}
          '';
        };
      }
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
