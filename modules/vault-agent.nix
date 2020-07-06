{ config, lib, pkgs, ... }:
let
  inherit (builtins) toJSON;
  inherit (lib) mkIf filter;

  # There's an issue where vault-agent may stop to make templates.
  # https://github.com/hashicorp/vault/pull/9200
  # For now we do the dirty thing and add a timer that just restarts this every
  # so often.
in {
  config = mkIf config.services.vault.enable {
    systemd.timers.vault-agent-restart = {
      wantedBy = [ "vault-agent.service" ];
      timerConfig = {
        OnActiveSec = "10m";
        OnUnitActiveSec = "10m";
      };
    };

    systemd.services.vault-agent-restart = {
      wantedBy = [ "vault-agent.service" ];
      before = [ "vault-agent.service" ];
      serviceConfig = {
        Type = "exec";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemctl restart vault-agent.service";
      };
    };

    systemd.services.vault-agent = {
      after = [ "vault.service" "consul.service" ];
      requires = [ "vault.service" "consul.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        inherit (config.environment.variables)
          AWS_DEFAULT_REGION VAULT_CACERT VAULT_ADDR VAULT_FORMAT;
      };

      serviceConfig = {
        Restart = "always";
        RestartSec = "30s";
      };

      path = with pkgs; [ vault-bin glibc gawk ];

      script = let
        vaultAgentConfig = pkgs.writeText "vault-agent.json" (toJSON {
          pid_file = "./vault-agent.pid";
          vault.address = "https://10.0.0.10:8200";
          # exit_after_auth = true;
          auto_auth = {
            method = [{
              type = "aws";
              config = {
                type = "iam";
                role = "core-iam";
                header_value = config.cluster.domain;
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

          templates = filter (t: t != null) [
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
                command = "${pkgs.systemd}/bin/systemctl restart nomad.service";
                destination = "/etc/nomad.d/consul-token.json";
                contents = ''
                  {{ with secret "consul/creds/nomad-server" }}
                  {
                    "consul": {
                      "token": "{{ .Data.token }}"
                    }
                  }
                  {{ end }}
                '';
              };
            } else
              null)

            (if config.services.vault.enable then {
              template = {
                command = "${pkgs.systemd}/bin/systemctl reload vault.service";
                destination = "/etc/vault.d/consul-token.json";
                contents = ''
                  {{ with secret "consul/creds/vault-server" }}
                  {
                    "service_registration": {
                      "consul": {
                        "token": "{{ .Data.token }}"
                      }
                    }
                  }
                  {{ end }}
                '';
              };
            } else
              null)
          ];
        });
      in "${pkgs.vault-bin}/bin/vault agent -config ${vaultAgentConfig}";
    };
  };
}
