{
  config,
  lib,
  pkgs,
  pkiFiles,
  ...
}: let
  isClient = config.services.vault-agent.role == "client";

  datacenter = config.currentCoreNode.datacenter or config.cluster.region;

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
    agentCommand [pkgs.systemd] "reload-${service}" "systemctl try-reload-or-restart ${service}";
  restart = service:
    agentCommand [pkgs.systemd] "restart-${service}" "systemctl try-restart ${service}";

  pkiAttrs = {
    common_name = "server.${datacenter}.consul";
    ip_sans = ["127.0.0.1"];
    alt_names = ["vault.service.consul" "consul.service.consul" "nomad.service.consul"];
    ttl = "700h";
  };

  pkiArgs = lib.flip lib.mapAttrsToList pkiAttrs (name: value:
    if builtins.isList value
    then ''"${name}=${lib.concatStringsSep "," value}"''
    else ''"${name}=${toString value}"'');

  pkiSecret = ''"pki/issue/client" ${toString pkiArgs}'';
in {
  services.vault-agent.templates = lib.mkIf isClient {
    "${pkiFiles.certChainFile}" = {
      command = restart "certs-updated.service";
      contents = ''
        {{ with secret ${pkiSecret} }}{{ .Data.certificate }}
        {{ range .Data.ca_chain }}{{ . }}
        {{ end }}{{ end }}
      '';
    };

    "${pkiFiles.caCertFile}" = {
      # TODO: this is the chain up to vault's intermediate CaCert, including the rootCaCert
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
