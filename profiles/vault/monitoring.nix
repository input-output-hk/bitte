{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ]; };

  Switches = {
    services.vault-agent-monitoring.enable = true;
  };

  Config = {
    services.vault-agent = {
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
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
