{ config, lib, pkgs, pkiFiles, ... }: let

  consulAgentToken = if config.services.vault-agent.disableTokenRotation.consulAgent then
    ''
      {{ with secret "kv/bootstrap/static-tokens/clients/consul-agent" }}{{ .Data.data.token }}{{ end }}''
  else
    ''{{ with secret "consul/creds/consul-agent" }}{{ .Data.token }}{{ end }}'';

  consulDefaultToken = if config.services.vault-agent.disableTokenRotation.consulDefault then
    ''
      {{ with secret "kv/bootstrap/static-tokens/clients/consul-default" }}{{ .Data.data.token }}{{ end }}''
  else
    ''
      {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}'';

  reload = service: "${pkgs.systemd}/bin/systemctl try-reload-or-restart ${service}";
  restart = service: "${pkgs.systemd}/bin/systemctl try-restart ${service}";

  pkiAttrs = {
    common_name = "server.${config.cluster.region}.consul";
    ip_sans = [ "127.0.0.1" ];
    alt_names =
      [ "vault.service.consul" "consul.service.consul" "nomad.service.consul" ];
    ttl = "700h";
  };

  pkiArgs = lib.flip lib.mapAttrsToList pkiAttrs (name: value:
    if builtins.isList value then
      ''"${name}=${lib.concatStringsSep "," value}"''
    else
      ''"${name}=${toString value}"'');

  pkiSecret = ''"pki/issue/client" ${toString pkiArgs}'';

in {
  services.vault-agent.templates = {
    "${pkiFiles.certChainFile}" = {
      contents = ''
        {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
        {{ range .Data.ca_chain }}{{ . }}
        {{ end }}{{ end }}
      '';
      command = restart "certs-updated.service";
    };

    "${pkiFiles.caCertFile}" = {
      # TODO: this is the chain up to vault's intermediate CaCert, includiong the rootCaCert
      # it is not the rootCaCert only
      contents = ''
        {{ with secret ${pkiSecret} }}{{ range .Data.ca_chain }}{{ . }}
        {{ end }}{{ end }}
      '';
      command = restart "certs-updated.service";
    };

    # exposed individually only for monitoring by telegraf
    "${pkiFiles.certFile}" = {
      contents = ''
        {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
        {{ end }}
      '';
      command = restart "certs-updated.service";
    };

    "${pkiFiles.keyFile}" = {
      contents = ''
        {{ with secret ${pkiSecret} }}{{ .Data.private_key }}{{ end }}
      '';
      command = restart "certs-updated.service";
    };

    "/etc/consul.d/tokens.json" = lib.mkIf config.services.consul.enable {
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
      command = restart "consul";
    };

    "/run/keys/consul-default-token" =
      lib.mkIf config.services.consul.enable {
        contents = ''
          ${consulDefaultToken}
        '';
        command = restart "consul.service";
      };

    "/run/keys/nomad-consul-token" = lib.mkIf config.services.nomad.enable {
      contents = ''
        ${consulDefaultToken}
      '';
      command = restart "nomad.service";
    };

    "/etc/vault.d/consul-token.json" =  lib.mkIf config.services.vault.enable {
      contents = ''
        {{ with secret "consul/creds/vault-client" }}
        {
          "storage": {
            "consul": {
              "token": "{{ .Data.token }}",
              "address": "127.0.0.1:8500",
              "tlsCaFile": pkiFiles.caCertFile,
              "tlsCertFile": pkiFiles.certChainFile,
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
      command = reload "vault.service";
    };
  };
}
