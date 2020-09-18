{ config, lib, pkgs, nodeName, ... }:
let
  inherit (builtins) toJSON isList;
  inherit (pkgs) writeShellScriptBin;
  inherit (lib) mkIf filter mkEnableOption concatStringsSep flip mapAttrsToList;
  inherit (config.cluster) domain region;
  inherit (config.cluster.instances.${nodeName}) privateIP;

  vaultAgentConfig = pkgs.toPrettyJSON "vault-agent" {
    pid_file = "./vault-agent.pid";
    vault.address = "https://127.0.0.1:8200";
    # exit_after_auth = true;
    auto_auth = {
      method = [{
        type = "aws";
        config = {
          type = "iam";
          role = "${config.cluster.name}-core";
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

    templates = let
      pkiAttrs = {
        common_name = "server.${region}.consul";
        ip_sans = [ "127.0.0.1" privateIP ];
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

      pkiArgs = flip mapAttrsToList pkiAttrs (name: value:
        if isList value then
          ''"${name}=${concatStringsSep "," value}"''
        else
          ''"${name}=${toString value}"'');

      pkiSecret = ''"pki/issue/server" ${toString pkiArgs}'';

      reload-cvn = writeShellScriptBin "reload-cvn" ''
        VAULT_TOKEN="$(< /run/keys/vault-token)"
        export VAULT_TOKEN

        set -x
        ${pkgs.systemd}/bin/systemctl reload consul.service
        ${pkgs.systemd}/bin/systemctl reload nomad.service
        ${pkgs.systemd}/bin/systemctl reload vault.service
        ${pkgs.systemd}/bin/systemctl restart ingress.service

        vault write nomad/config/access \
          ca_cert=@/etc/ssl/certs/full.pem \
          client_cert=@/etc/ssl/certs/cert.pem \
          client_key=@/var/lib/vault/cert-key.pem

        exit 0
      '';

    in filter (t: t != null) [
      (if config.services.consul.enable then {
        template = {
          destination = "/etc/consul.d/tokens.json";
          command = "${pkgs.systemd}/bin/systemctl reload consul.service";
          contents = ''
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
      } else
        null)

      (if config.services.nomad.enable then {
        template = {
          command =
            "${pkgs.systemd}/bin/systemctl reload nomad.service || ${pkgs.systemd}/bin/systemctl restart nomad.service";
          destination = "/etc/nomad.d/consul-token.json";
          contents = ''

            {
              "consul": {
                "token": "{{ with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end }}"
              }
            }
            {{ end }}
          '';
        };
      } else
        null)
    ];
  };

in {
  options = {
    services.vault-agent-core.enable =
      mkEnableOption "Start vault-agent for cores";
  };

  config = mkIf config.services.vault-agent-core.enable {
    systemd.services.vault-agent = {
      after = [ "vault.service" "consul.service" ];
      wants = [ "vault.service" "consul.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        inherit (config.environment.variables) AWS_DEFAULT_REGION VAULT_FORMAT;
        VAULT_CACERT = "/etc/ssl/certs/full.pem";
        CONSUL_HTTP_ADDR = "127.0.0.1:8500";
        CONSUL_CACERT = "/etc/ssl/certs/full.pem";

        # TODO: figure out why we sometimes cannot renew the certificate.
        # Is it related to IAM session length?
        # This should definitely verify, but is too fragile right now.
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
