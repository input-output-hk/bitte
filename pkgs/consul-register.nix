{ lib, consul, vault-bin, coreutils, writeShellScriptBin, toPrettyJSON }:
{ creds ? "consul-register", extraServiceConfig ? { }, service }:
let
  serviceJson = toPrettyJSON service.name {
    service = service // {
      checks = lib.flip lib.mapAttrsToList (service.checks or { })
        (checkName: check:
          {
            id = "${service.name}-${checkName}";
            service_id = service.name;
            name = checkName;
          } // check);
    };
  };

  PATH = lib.makeBinPath [ coreutils consul vault-bin ];

  common = ''
    set -euo pipefail

    PATH="${PATH}"

    export VAULT_TOKEN="$(< /run/keys/vault-token)"
    CONSUL_HTTP_TOKEN="$(
      vault read \
        -tls-skip-verify \
        -address https://active.vault.service.consul:8200 \
        -field token \
        consul/creds/${creds}
    )"
    export CONSUL_HTTP_TOKEN

    set -x
  '';
in rec {
  deregister = writeShellScriptBin "${service.name}-deregister" ''
    ${common}
    consul services deregister ${serviceJson}
  '';

  register = writeShellScriptBin "${service.name}-register" ''
    ${common}
    consul services register ${serviceJson}
    while true; do sleep 1440; done
  '';

  systemdService = {
    wantedBy = [ "${service.name}.service" ];
    partOf = [ "${service.name}.service" ];

    environment = {
      VAULT_ADDR = "https://127.0.0.1:8200";
      VAULT_CACERT = config.age.secrets.vault-ca.path;
      CONSUL_HTTP_ADDR = "127.0.0.1:8500";
      CONSUL_CACERT = config.age.secrets.consul-ca.path;
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = "15s";
      ExecStart = "${register}/bin/${service.name}-register";
      ExecStopPost = "${deregister}/bin/${service.name}-deregister";
    } // extraServiceConfig;
  };
}
