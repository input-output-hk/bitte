{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ]; };

  Switches = {
    services.vault-agent-core.enable = true;
    services.vault.enable = lib.mkForce false;
  };

  Config = {
    services.vault-agent-core = {
      vaultAddress = "https://core.vault.service.consul:8200";
    };
    services.vault-agent = {

      listener = [{
        type = "tcp";
        address = "127.0.0.1:8200";
        tlsDisable = true;
      }];

      templates = let
        command =
          "${pkgs.systemd}/bin/systemctl try-restart --no-block ingress.service";
      in {
        "/etc/ssl/certs/${config.cluster.domain}-cert.pem" = {
          contents = ''
            {{ with secret "kv/bootstrap/letsencrypt/cert" }}{{ .Data.data.value }}{{ end }}
          '';
          inherit command;
        };

        "/etc/ssl/certs/${config.cluster.domain}-full.pem" = {
          contents = ''
            {{ with secret "kv/bootstrap/letsencrypt/fullchain" }}{{ .Data.data.value }}{{ end }}
          '';
          inherit command;
        };

        "/etc/ssl/certs/${config.cluster.domain}-key.pem" = {
          contents = ''
            {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
          '';
          inherit command;
        };

        "/etc/ssl/certs/${config.cluster.domain}-full.pem.key" = {
          contents = ''
            {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
          '';
          inherit command;
        };
      };
    };

    environment.variables.VAULT_ADDR = "http://127.0.0.1:8200";
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
