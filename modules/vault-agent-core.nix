{ config, lib, pkgs, nodeName, ... }:
let
  inherit (pkgs) writeShellScriptBin;
  inherit (config.cluster) domain region;
  instance = config.cluster.instances.${nodeName};

  runIf = cond: value: if cond then value else null;
  compact = lib.filter (value: value != null);

  vaultAgentConfig = pkgs.toPrettyJSON "vault-agent" {
    pid_file = "/run/vault-agent.pid";

    vault = {
      address = config.services.vault-agent-core.vaultAddress;
      ca_cert = config.age.secrets.vault-ca.path;
      client_cert = config.age.secrets.vault-client.path;
      client_key = config.age.secrets.vault-client-key.path;
    };

    auto_auth = {
      method = [{
        type = "cert";
        config = {
          name = "vault-agent-core";
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

    templates = let
      pkiAttrs = {
        common_name = "server.${region}.consul";
        ip_sans = [ "127.0.0.1" instance.privateIP nodeName ];
        alt_names = [
          "vault.service.consul"
          "consul.service.consul"
          "nomad.service.consul"
          "server.${region}.consul"
          "vault.${domain}"
          "consul.${domain}"
          "nomad.${domain}"
          "monitoring.${domain}"
          "127.0.0.1"
        ];
        ttl = "322h";
      };

      pkiArgs = lib.flip lib.mapAttrsToList pkiAttrs (name: value:
        if builtins.isList value then
          ''"${name}=${lib.concatStringsSep "," value}"''
        else
          ''"${name}=${toString value}"'');

      pkiSecret = ''"pki/issue/server" ${toString pkiArgs}'';

      reload-cvn = writeShellScriptBin "reload-cvn" ''
        VAULT_TOKEN="$(< /run/keys/vault-token)"
        export VAULT_TOKEN

        set -x

        sleep 10

        ${pkgs.systemd}/bin/systemctl try-reload-or-restart consul.service
        ${pkgs.systemd}/bin/systemctl try-reload-or-restart nomad.service
        ${pkgs.systemd}/bin/systemctl try-reload-or-restart vault.service
        ${pkgs.systemd}/bin/systemctl try-reload-or-restart ingress.service

        vault write nomad/config/access \
          ca_cert=@/etc/ssl/certs/full.pem \
          client_cert=@/etc/ssl/certs/cert.pem \
          client_key=@/var/lib/vault/cert-key.pem

        exit 0
      '';

    in compact [
      (runIf config.services.consul.enable {
        template = {
          destination = "/etc/consul.d/tokens.json";
          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart consul.service";
          contents = if nodeName == "monitoring" then ''
            {
              "acl": {
                "tokens": {
                  "agent": "{{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}"
                }
              }
            }
          '' else ''
            {
              "acl": {
                "tokens": {
                  "default": "{{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}",
                  "agent": "{{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}"
                }
              }
            }
          '';
        };
      })

      (runIf config.services.consul.enable {
        template = {
          destination = "/run/keys/consul-default-token";
          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart consul.service";
          contents = ''
            {{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}
          '';
        };
      })

      # TODO: remove duplication
      (runIf config.services.nomad.enable {
        template = {
          command = "${pkgs.systemd}/bin/systemctl try-restart nomad.service";
          destination = "/etc/nomad.d/consul-token.json";
          contents = ''
            {
              "consul": {
                "token": "{{ with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end }}"
              }
            }
          '';
        };
      })

      (runIf config.services.nomad.enable {
        template = {
          command = "${pkgs.systemd}/bin/systemctl try-restart nomad.service";
          destination = "/run/keys/nomad-consul-token";
          contents = ''
            {{- with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end -}}
          '';
        };
      })

      (runIf config.services.nomad-autoscaler.enable {
        template = {
          command =
            "${pkgs.systemd}/bin/systemctl try-reload-or-restart nomad-autoscaler.service";
          destination = "/run/keys/nomad-autoscaler-token";
          contents = ''
            {{- with secret "nomad/creds/nomad-autoscaler" }}{{ .Data.secret_id }}{{ end -}}
          '';
        };
      })
    ];
  };

in {
  options = {
    services.vault-agent-core = {
      enable = lib.mkEnableOption "Start vault-agent for cores";
      vaultAddress = lib.mkOption {
        type = lib.types.str;
        default = "https://127.0.0.1:8200";
      };
    };
  };

  config = lib.mkIf config.services.vault-agent-core.enable {
    systemd.services.vault-agent = {
      after = [ "vault.service" "consul.service" ];
      wants = [ "vault.service" "consul.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        inherit (config.environment.variables) AWS_DEFAULT_REGION;
        CONSUL_CACERT = config.age.secrets.consul-ca.path;
        CONSUL_HTTP_ADDR = "127.0.0.1:8500";
      };

      path = with pkgs; [ vault-bin ];

      serviceConfig = {
        Restart = "always";
        RestartSec = "30s";
      };

      script = ''
        set -exuo pipefail
        echo "======================"
        ls -la /var/lib/vault/
        echo address = ${config.services.vault-agent-core.vaultAddress}
        echo ca_cert = ${config.age.secrets.vault-ca.path}
        echo client_cert = ${config.age.secrets.vault-client.path}
        echo client_key = ${config.age.secrets.vault-client-key.path}
        echo "======================"
        exec ${pkgs.vault-bin}/bin/vault agent -config ${vaultAgentConfig}
      '';
    };
  };
}
