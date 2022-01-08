{ config, lib, pkgs, pkiFiles, ... }: let

  reload = service: "${pkgs.systemd}/bin/systemctl --no-block try-reload-or-restart ${service}";
  restart = service: "${pkgs.systemd}/bin/systemctl --no-block try-restart ${service}";

in {
  services.vault-agent.templates = {
    "/etc/ssl/certs/${config.cluster.domain}-cert.pem" = {
      command = restart "ingress.service";
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/cert" }}{{ .Data.data.value }}{{ end }}
      '';
    };

    "/etc/ssl/certs/${config.cluster.domain}-full.pem" = {
      command = restart "ingress.service";
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/fullchain" }}{{ .Data.data.value }}{{ end }}
      '';
    };

    "/etc/ssl/certs/${config.cluster.domain}-key.pem" = {
      command = restart "ingress.service";
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
      '';
    };

    "/etc/ssl/certs/${config.cluster.domain}-full.pem.key" = {
      command = restart "ingress.service";
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
      '';
    };
  };
}
