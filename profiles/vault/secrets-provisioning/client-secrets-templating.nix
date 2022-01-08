{ config, lib, pkgs, pkiFiles, ... }: let

  consulAgentToken = if config.services.vault-agent.disableTokenRotation.consulAgent
  then ''{{ with secret "kv/bootstrap/static-tokens/clients/consul-agent" }}{{ .Data.data.token }}{{ end }}''
  else ''{{ with secret "consul/creds/consul-agent" }}{{ .Data.token }}{{ end }}'';

  consulDefaultToken = if config.services.vault-agent.disableTokenRotation.consulDefault
  then ''{{ with secret "kv/bootstrap/static-tokens/clients/consul-default" }}{{ .Data.data.token }}{{ end }}''
  else ''{{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}'';

  reload = service: "${pkgs.systemd}/bin/systemctl try-reload-or-restart ${service}";
  restart = service: "${pkgs.systemd}/bin/systemctl try-restart ${service}";

in {
  services.vault-agent.templates = {
    "/etc/consul.d/tokens.json" = lib.mkIf config.services.consul.enable {
      command = restart "consul";
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
    };

    "/run/keys/consul-default-token" = lib.mkIf config.services.consul.enable {
      command = restart "consul.service";
      contents = ''
        ${consulDefaultToken}
      '';
    };

    "/run/keys/nomad-consul-token" = lib.mkIf config.services.nomad.enable {
      command = restart "nomad.service";
      contents = ''
        ${consulDefaultToken}
      '';
    };

    "/etc/vault.d/consul-token.json" =  lib.mkIf config.services.vault.enable {
      command = reload "vault.service";
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
    };
  };
}
