{ lib, consul, vault-bin, glibc, gawk, coreutils, writeShellScriptBin
, toPrettyJSON }:
{ creds ? "consul-register", extraServiceConfig ? { }, service }:
let
  serviceJson = toPrettyJSON service.name {
    service = (service // {
      checks = lib.flip lib.mapAttrsToList (service.checks or { })
        (checkName: check:
          {
            id = service.name;
            service_id = service.name;
            name = checkName;
          } // check);
    });
  };

  PATH = lib.makeBinPath [ coreutils consul vault-bin glibc gawk ];

  common = ''
    set -euo pipefail

    PATH="${PATH}"

    VAULT_TOKEN="$(vault login -method aws -no-store -token-only)"
    export VAULT_TOKEN
    CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/${creds})"
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
      VAULT_CACERT = "/etc/ssl/certs/full.pem";
      CONSUL_HTTP_ADDR = "127.0.0.1:8500";
      CONSUL_CACERT = "/etc/ssl/certs/full.pem";
    };

    serviceConfig = {
      Restart = "always";
      RestartSec = "15s";
      ExecStart = "${register}/bin/${service.name}-register";
      ExecStopPost = "${deregister}/bin/${service.name}-deregister";
      DynamicUser = true;
    } // extraServiceConfig;
  };
}
