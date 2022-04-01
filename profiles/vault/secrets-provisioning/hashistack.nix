{ config, lib, pkgs, hashiTokens, ... }:
let
  roles = let
    reload = service:
      "${pkgs.systemd}/bin/systemctl --no-block try-reload-or-restart ${service} || true";
    restart = service:
      "${pkgs.systemd}/bin/systemctl --no-block try-restart ${service} || true";
  in {
    core = rec {
      inherit reload restart;

      consulNomad = ''
        {{- with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end -}}'';
      nomadAutoscaler = ''
        {{- with secret "nomad/creds/nomad-autoscaler" }}{{ .Data.secret_id }}{{ end -}}'';
      nomadSnapshot = ''
        {{- with secret "nomad/creds/management" }}{{ .Data.secret_id }}{{ end -}}'';
      nomadConsul = ''
        {
          "consul": {
            "token": "${consulNomad}"
          }
        }
      '';

      consulAgent =
        if config.services.vault-agent.disableTokenRotation.consulAgent then
          ''
            {{ with secret "kv/bootstrap/static-tokens/cores/consul-server-agent" }}{{ .Data.data.token }}{{ end }}''
        else
          ''
            {{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}'';

      consulDefault =
        if config.services.vault-agent.disableTokenRotation.consulDefault then
          ''
            {{ with secret "kv/bootstrap/static-tokens/cores/consul-server-default" }}{{ .Data.data.token }}{{ end }}''
        else
          ''
            {{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}'';

      consulACL = ''
        {
          "acl": {
            "tokens": {
              "agent": "${consulAgent}",
              "default": "${consulDefault}"
            }
          }
        }
      '';
    };

    client = rec {
      inherit reload restart;

      consulAgent =
        if config.services.vault-agent.disableTokenRotation.consulAgent then
          ''
            {{ with secret "kv/bootstrap/static-tokens/clients/consul-agent" }}{{ .Data.data.token }}{{ end }}''
        else
          ''
            {{ with secret "consul/creds/consul-agent" }}{{ .Data.token }}{{ end }}'';

      consulDefault =
        if config.services.vault-agent.disableTokenRotation.consulDefault then
          ''
            {{ with secret "kv/bootstrap/static-tokens/clients/consul-default" }}{{ .Data.data.token }}{{ end }}''
        else
          ''
            {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}'';

      consulNomad = consulDefault;

      nomadConsul = ''
        {
          "consul": {
            "token": "${consulNomad}"
          }
        }
      '';

      consulACL = ''
        {
          "acl": {
            "tokens": {
              "agent": "${consulAgent}",
              "default": "${consulDefault}"
            }
          }
        }
      '';
    };

    routing = rec {
      inherit reload restart;
      inherit (roles.client) consulAgent consulNomad;
      consulDefault = ''
        {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}'';
      traefik =
        ''{{ with secret "consul/creds/traefik" }}{{ .Data.token }}{{ end }}'';

      consulACL = ''
        {
          "acl": {
            "tokens": {
              "agent": "${consulAgent}"
            }
          }
        }
      '';
    };

    hydra = rec {
      inherit reload restart;
      inherit (roles.client) consulAgent consulNomad;
      consulDefault = ''
        {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}'';
      traefik =
        ''{{ with secret "consul/creds/traefik" }}{{ .Data.token }}{{ end }}'';

      consulACL = ''
        {
          "acl": {
            "tokens": {
              "agent": "${consulAgent}",
              "default": "${consulDefault}"
            }
          }
        }
      '';
    };
  };

  roleName = config.services.vault-agent.role;
  role = roles."${roleName}";
  isClient = roleName == "client";
  isRouting = roleName == "routing";
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
      "${hashiTokens.consul-default}" = lib.mkIf config.services.consul.enable {
        command = role.restart "consul.service";
        contents = role.consulDefault;
      };

      "${hashiTokens.consul-nomad}" = lib.mkIf config.services.nomad.enable {
        command = role.restart "nomad.service";
        contents = role.consulNomad;
      };

      "${hashiTokens.nomad-autoscaler}" =
        lib.mkIf config.services.nomad-autoscaler.enable {
          command = role.reload "nomad-autoscaler.service";
          contents = role.nomadAutoscaler;
        };

      "${hashiTokens.nomad-snapshot}" =
        lib.mkIf config.services.nomad-snapshots.enable {
          contents = role.nomadSnapshot;
        };

      "${hashiTokens.consuld-json}" = lib.mkIf config.services.consul.enable {
        command = role.restart "consul.service";
        contents = role.consulACL;
      };

      "${hashiTokens.nomadd-consul-json}" =
        lib.mkIf (config.services.nomad.enable && isClient) {
          command = role.restart "nomad.service";
          contents = role.nomadConsul;
        };

      "${hashiTokens.traefik}" = lib.mkIf isRouting {
        command = role.restart "traefik.service";
        contents = role.traefik;
      };
    };
  };
}
