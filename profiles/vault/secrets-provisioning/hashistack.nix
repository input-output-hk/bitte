{ config, lib, pkgs, hashiTokens, ... }: let

  clientsConsulAgentToken = if config.services.vault-agent.disableTokenRotation.consulAgent
  then ''{{ with secret "kv/bootstrap/static-tokens/clients/consul-agent" }}{{ .Data.data.token }}{{ end }}''
  else ''{{ with secret "consul/creds/consul-agent" }}{{ .Data.token }}{{ end }}'';

  clientsConsulDefaultToken = if config.services.vault-agent.disableTokenRotation.consulDefault
  then ''{{ with secret "kv/bootstrap/static-tokens/clients/consul-default" }}{{ .Data.data.token }}{{ end }}''
  else ''{{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}'';

  coresConsulAgentToken = if config.services.vault-agent.disableTokenRotation.consulAgent
  then ''{{ with secret "kv/bootstrap/static-tokens/cores/consul-server-agent" }}{{ .Data.data.token }}{{ end }}''
  else ''{{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}'';

  coresConsulDefaultToken = if config.services.vault-agent.disableTokenRotation.consulDefault
  then ''{{ with secret "kv/bootstrap/static-tokens/cores/consul-server-default" }}{{ .Data.data.token }}{{ end }}''
  else ''{{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}'';

  reload-client = service: "${pkgs.systemd}/bin/systemctl            try-reload-or-restart ${service}";
  reload-server = service: "${pkgs.systemd}/bin/systemctl --no-block try-reload-or-restart ${service} || true";
  restart-client = service: "${pkgs.systemd}/bin/systemctl            try-restart ${service}";
  restart-server = service: "${pkgs.systemd}/bin/systemctl --no-block try-restart ${service} || true";

  isClient = config.services.vault-agent.role == "client";

in {
  services.vault-agent = {
    sinks = [{
      sink = {
        type = "file";
        config = { path = hashiTokens.vault; };
        perms = "0644";
      };
    }];
    templates = {

      ${hashiTokens.consul-default} = lib.mkIf config.services.consul.enable ( if isClient
      then {
        command = restart-client "consul.service";
        contents = ''
          ${clientsConsulDefaultToken}
        '';
      } else {
        command = reload-server "consul.service";
        contents = ''
          ${coresConsulDefaultToken}
        '';
      });

      ${hashiTokens.consul-nomad} = lib.mkIf config.services.nomad.enable ( if isClient
      then {
        command = restart-client "nomad.service";
        contents = ''
          ${clientsConsulDefaultToken}
        '';
      } else {
        command = restart-server "nomad.service";
        contents = ''
          {{- with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end -}}
        '';
      });

      ${hashiTokens.nomad-autoscaler} = lib.mkIf (config.services.nomad-autoscaler.enable && !isClient) {
        command = reload-server "nomad-autoscaler.service";
        contents = ''
          {{- with secret "nomad/creds/nomad-autoscaler" }}{{ .Data.secret_id }}{{ end -}}
        '';
      };

      ${hashiTokens.nomad-snapshot} = lib.mkIf (config.services.nomad-snapshots.enable && !isClient) {
        contents = ''
          {{- with secret "nomad/creds/management" }}{{ .Data.secret_id }}{{ end -}}
        '';
      };


      "/etc/consul.d/tokens.json" = lib.mkIf config.services.consul.enable ( if isClient
        then {
          command = restart-client "consul";
          contents = ''
            { "encrypt": "{{ with secret "kv/bootstrap/clients/consul" }}{{ .Data.data.encrypt }}{{ end }}",
              "acl": {
                "tokens": {
                  "agent": "${clientsConsulAgentToken}",
                  "default": "${clientsConsulDefaultToken}"
                }
            }}
          '';
        } else {
          command = reload-server "consul.service";
          contents = ''
            { "acl": {
                "tokens": {
                  "agent": "${coresConsulAgentToken}",
                  "default": "${coresConsulDefaultToken}"
                }
            }}
          '';
        });

      # TODO: remove duplication
      "/etc/nomad.d/consul-token.json" = lib.mkIf (config.services.nomad.enable && !isClient) {
        command = restart-server "nomad.service";
        contents = ''
          {
            "consul": {
              "token": "{{ with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end }}"
            }
          }
        '';
      };

      "/etc/vault.d/consul-token.json" =  lib.mkIf (config.services.vault.enable && isClient) {
        command = reload-client "vault.service";
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
      };
    };
  };
}
