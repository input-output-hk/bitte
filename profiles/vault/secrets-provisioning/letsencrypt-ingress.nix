{ config, lib, pkgs, letsencryptCertMaterial, ... }: let

  # assumes: routing has uploaded letsencrypt cert material

  reload = service: "${pkgs.systemd}/bin/systemctl --no-block try-reload-or-restart ${service}";
  restart = service: "${pkgs.systemd}/bin/systemctl --no-block try-restart ${service}";

in {
  services.vault-agent.templates = {
    ${letsencryptCertMaterial.certFile} = {
      command = restart "ingress.service";
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/cert" }}{{ .Data.data.value }}{{ end }}
      '';
    };

    ${letsencryptCertMaterial.certChainFile} = {
      command = restart "ingress.service";
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/fullchain" }}{{ .Data.data.value }}{{ end }}
      '';
    };

    ${letsencryptCertMaterial.keyFile} = {
      command = restart "ingress.service";
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
      '';
    };

    # This is a tacit expansion from haproxy during runtime nd only identifiable via
    # ${letsencryptCertMaterial.keyFile} in the haproxy config.
    # Usually, haproxy tutorials recommend concatenating the key into the cert file,
    # but this is not a representation that we prefer
    "${letsencryptCertMaterial.certChainFile}.key" = {
      command = restart "ingress.service";
      contents = ''
        {{ with secret "kv/bootstrap/letsencrypt/key" }}{{ .Data.data.value }}{{ end }}
      '';
    };
  };
}
