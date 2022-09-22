{
  config,
  lib,
  pkgs,
  hashiTokens,
  ...
}: let
  roles = let
    agentCommand = runtimeInputs: namePrefix: cmds: let
      script = pkgs.writeShellApplication {
        inherit runtimeInputs;
        name = "${namePrefix}.sh";
        text = ''
          set -x
          ${cmds}
        '';
      };
    in "${script}/bin/${namePrefix}.sh";
    # Vault has deprecated use of `command` in the template stanza, but a bug
    # prevents us from moving to the `exec` statement until resolved:
    # Ref: https://github.com/hashicorp/vault/issues/16230
    # in { command = [ "${script}/bin/${namePrefix}.sh" ]; };

    reload = service:
      agentCommand [pkgs.systemd] "reload-${service}" "systemctl --no-block try-reload-or-restart ${service} || true";
    restart = service:
      agentCommand [pkgs.systemd] "restart-${service}" "systemctl --no-block try-restart ${service} || true";
  in {
    core = rec {
      inherit reload restart;

      consulNomad = ''
        {{- with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end -}}'';
      nomadAutoscaler = ''
        {{- with secret "nomad/creds/nomad-autoscaler" }}{{ .Data.secret_id }}{{ end -}}'';
      nomadSnapshot = ''
        {{- with secret "nomad/creds/management" }}{{ .Data.secret_id }}{{ end -}}'';

      consulAgent =
        if config.services.vault-agent.disableTokenRotation.consulAgent
        then ''
          {{ with secret "kv/bootstrap/static-tokens/core/consul-server-agent" }}{{ .Data.data.token }}{{ end }}''
        else ''
          {{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}'';

      consulDefault =
        if config.services.vault-agent.disableTokenRotation.consulDefault
        then ''
          {{ with secret "kv/bootstrap/static-tokens/core/consul-server-default" }}{{ .Data.data.token }}{{ end }}''
        else ''
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
        if config.services.vault-agent.disableTokenRotation.consulAgent
        then ''
          {{ with secret "kv/bootstrap/static-tokens/clients/consul-agent" }}{{ .Data.data.token }}{{ end }}''
        else ''
          {{ with secret "consul/creds/consul-agent" }}{{ .Data.token }}{{ end }}'';

      consulDefault =
        if config.services.vault-agent.disableTokenRotation.consulDefault
        then ''
          {{ with secret "kv/bootstrap/static-tokens/clients/consul-default" }}{{ .Data.data.token }}{{ end }}''
        else ''
          {{ with secret "consul/creds/consul-default" }}{{ .Data.token }}{{ end }}'';

      consulNomad = consulDefault;

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
      inherit (roles.client) consulAgent consulDefault consulNomad;

      traefik =
        if config.services.vault-agent.disableTokenRotation.routing
        then ''
          {{ with secret "kv/bootstrap/static-tokens/routing/traefik" }}{{ .Data.data.token }}{{ end }}''
        else ''
          {{ with secret "consul/creds/traefik" }}{{ .Data.token }}{{ end }}'';

      # Consul on routing excludes a default token for ACL security purposes.
      # This has the side effect of preventing local consul DNS lookups on routing.
      # Dnsmasq on routing is therefore configured to forward consul DNS requests to core nodes.
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

    cache = rec {
      inherit reload restart;
      inherit (roles.client) consulAgent consulDefault consulNomad;

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
  isRouting = roleName == "routing";
in {
  services.vault-agent = {
    sinks = [
      {
        sink = {
          type = "file";
          config = {path = hashiTokens.vault;};
          perms = "0644";
        };
      }
    ];

    templates = {
      "${hashiTokens.consul-default}" = lib.mkIf config.services.consul.enable {
        command = role.restart "consul.service";
        contents = role.consulDefault;
      };

      "${hashiTokens.consul-nomad}" = lib.mkIf config.services.nomad.enable {
        command = role.restart "nomad.service";
        contents = role.consulNomad;
      };

      "${hashiTokens.nomad-autoscaler}" = lib.mkIf config.services.nomad-autoscaler.enable {
        command = role.reload "nomad-autoscaler.service";
        contents = role.nomadAutoscaler;
      };

      "${hashiTokens.nomad-snapshot}" = lib.mkIf config.services.hashi-snapshots.enableNomad {
        contents = role.nomadSnapshot;
      };

      "${hashiTokens.consuld-json}" = lib.mkIf config.services.consul.enable {
        command = role.restart "consul.service";
        contents = role.consulACL;
      };

      "${hashiTokens.traefik}" = lib.mkIf isRouting {
        command = role.restart "traefik.service";
        contents = role.traefik;
      };
    };
  };
}
