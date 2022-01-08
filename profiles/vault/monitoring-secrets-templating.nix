{ config, lib, pkgs, pkiFiles, ... }: let

  reload = service: "${pkgs.systemd}/bin/systemctl try-reload-or-restart --no-block ${service}";
  restart = service: "${pkgs.systemd}/bin/systemctl try-restart --no-block ${service}";

in {
  services.vault-agent.templates = {
    "/etc/ssl/certs/${config.cluster.domain}-cert.pem" = {
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/cert" }}{{ .Data.data.value }}{{ end }}
      '';
      command = restart "ingress.service";
    };

    "/etc/ssl/certs/${config.cluster.domain}-full.pem" = {
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/fullchain" }}{{ .Data.data.value }}{{ end }}
      '';
      command = restart "ingress.service";
    };

    "/etc/ssl/certs/${config.cluster.domain}-key.pem" = {
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
      '';
      command = restart "ingress.service";
    };

    "/etc/ssl/certs/${config.cluster.domain}-full.pem.key" = {
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
      '';
      command = restart "ingress.service";
    };
  };
}
