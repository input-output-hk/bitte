{ config, lib, pkgs, pkiFiles, ... }: let

  reload = service: "${pkgs.systemd}/bin/systemctl try-reload-or-restart ${service}";
  restart = service: "${pkgs.systemd}/bin/systemctl try-restart ${service}";

  pkiAttrs = {
    common_name = "server.${config.cluster.region}.consul";
    ip_sans = [ "127.0.0.1" ];
    alt_names =
      [ "vault.service.consul" "consul.service.consul" "nomad.service.consul" ];
    ttl = "700h";
  };

  pkiArgs = lib.flip lib.mapAttrsToList pkiAttrs (name: value:
    if builtins.isList value then
      ''"${name}=${lib.concatStringsSep "," value}"''
    else
      ''"${name}=${toString value}"'');

  pkiSecret = ''"pki/issue/client" ${toString pkiArgs}'';

in {
  services.vault-agent.templates = {
    "${pkiFiles.certChainFile}" = {
      command = restart "certs-updated.service";
      contents = ''
        {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
        {{ range .Data.ca_chain }}{{ . }}
        {{ end }}{{ end }}
      '';
    };

    "${pkiFiles.caCertFile}" = {
      # TODO: this is the chain up to vault's intermediate CaCert, includiong the rootCaCert
      # it is not the rootCaCert only
      command = restart "certs-updated.service";
      contents = ''
        {{ with secret ${pkiSecret} }}{{ range .Data.ca_chain }}{{ . }}
        {{ end }}{{ end }}
      '';
    };

    # exposed individually only for monitoring by telegraf
    "${pkiFiles.certFile}" = {
      command = restart "certs-updated.service";
      contents = ''
        {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
        {{ end }}
      '';
    };

    "${pkiFiles.keyFile}" = {
      command = restart "certs-updated.service";
      contents = ''
        {{ with secret ${pkiSecret} }}{{ .Data.private_key }}{{ end }}
      '';
    };
  };
}
