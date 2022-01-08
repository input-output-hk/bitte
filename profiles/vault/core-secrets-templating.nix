{ config, lib, pkgs, pkiFiles, ... }: let

  consulAgentToken = if config.services.vault-agent.disableTokenRotation.consulAgent then
    ''
      {{ with secret "kv/bootstrap/static-tokens/cores/consul-server-agent" }}{{ .Data.data.token }}{{ end }}''
  else
    ''
      {{ with secret "consul/creds/consul-server-agent" }}{{ .Data.token }}{{ end }}'';

  consulDefaultToken = if config.services.vault-agent.disableTokenRotation.consulDefault then
    ''
      {{ with secret "kv/bootstrap/static-tokens/cores/consul-server-default" }}{{ .Data.data.token }}{{ end }}''
  else
    ''
      {{ with secret "consul/creds/consul-server-default" }}{{ .Data.token }}{{ end }}'';

  reload = pkgs.writeShellScript "reload.sh" ''
    ${pkgs.systemd}/bin/systemctl --no-block try-reload-or-restart $1 || true
  '';

  restart = pkgs.writeShellScript "reload.sh" ''
    ${pkgs.systemd}/bin/systemctl --no-block try-restart $1 || true
  '';

in {
  services.vault-agent.templates = {
    "/etc/consul.d/tokens.json" = lib.mkIf config.services.consul.enable {
      command = "${reload} consul.service";
      contents = ''
        {
          "acl": {
            "tokens": {
              "agent": "${consulAgentToken}",
              "default": "${consulDefaultToken}"
            }
          }
        }
      '';
    };

    "/run/keys/consul-default-token" =
      lib.mkIf config.services.consul.enable {
        command = "${reload} consul.service";
        contents = ''
          ${consulDefaultToken}
        '';
      };

    # TODO: remove duplication
    "/etc/nomad.d/consul-token.json" =
      lib.mkIf config.services.nomad.enable {
        command = "${restart} nomad.service";
        contents = ''
          {
            "consul": {
              "token": "{{ with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end }}"
            }
          }
        '';
      };

    "/run/keys/nomad-consul-token" = lib.mkIf config.services.nomad.enable {
      command = "${restart} nomad.service";
      contents = ''
        {{- with secret "consul/creds/nomad-server" }}{{ .Data.token }}{{ end -}}
      '';
    };

    "/run/keys/nomad-autoscaler-token" =
      lib.mkIf config.services.nomad-autoscaler.enable {
        command = "${reload} nomad-autoscaler.service";
        contents = ''
          {{- with secret "nomad/creds/nomad-autoscaler" }}{{ .Data.secret_id }}{{ end -}}
        '';
      };

    "/run/keys/nomad-snapshot-token" =
      lib.mkIf config.services.nomad-snapshots.enable {
        contents = ''
          {{- with secret "nomad/creds/management" }}{{ .Data.secret_id }}{{ end -}}
        '';
      };

  };
}
