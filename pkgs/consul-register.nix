{
  lib,
  consul,
  vault-bin,
  coreutils,
  writeShellScriptBin,
  toPrettyJSON,
}: {
  creds ? "consul-register",
  systemdServiceDep ? service.name,
  extraServiceConfig ? {},
  service,
  pkiFiles,
}: let
  serviceJson = toPrettyJSON service.name {
    service =
      service
      // {
        checks =
          lib.flip lib.mapAttrsToList (service.checks or {})
          (checkName: check:
            {
              id = "${service.name}-${checkName}";
              service_id = service.name;
              name = checkName;
            }
            // check);
      };
  };

  PATH = lib.makeBinPath [coreutils consul vault-bin];

  common = ''
    set -euo pipefail
    set +x

    PATH="${PATH}"

    export VAULT_TOKEN="$(< /run/keys/vault-token)"
    CONSUL_HTTP_TOKEN="$(
      vault read \
        -tls-skip-verify \
        -address http://127.0.0.1:8200 \
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
    while true; do
      if ! consul acl token read -self &> /dev/null; then
        ${common}
      fi

      consul services register ${serviceJson}

      sleep 60
    done
  '';

  systemdService = {
    wantedBy = ["${systemdServiceDep}.service"];
    partOf = ["${systemdServiceDep}.service"];
    after = ["consul.service" "vault-agent.service"];
    wants = ["consul.service" "vault-agent.service"];

    environment = {
      VAULT_ADDR = "https://127.0.0.1:8200";
      VAULT_CACERT = pkiFiles.caCertFile;
      CONSUL_HTTP_ADDR = "127.0.0.1:8500";
      CONSUL_CACERT = pkiFiles.caCertFile;
    };

    serviceConfig =
      {
        Restart = "always";
        RestartSec = "15s";
        ExecStart = "${register}/bin/${service.name}-register";
        ExecStopPost = "${deregister}/bin/${service.name}-deregister";
      }
      // extraServiceConfig;
  };
}
