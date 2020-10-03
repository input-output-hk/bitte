{ name, json, writeShellScriptBin }:
writeShellScriptBin "nomad-run" ''
  echo running ${json}

  set -euo pipefail

  vault token lookup "$(vault print token)" &> /dev/null \
  || vault login -method github -path github-employees -no-print

  NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/admin)"
  export NOMAD_TOKEN

  CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/admin)"
  export CONSUL_HTTP_TOKEN

  cache="$(nix eval ".#clusters.$BITTE_CLUSTER.proto.config.cluster.s3Cache" --raw)"

  nix copy --to "$cache&secret-key=secrets/nix-secret-key-file" ${json}

  jq --arg token "$CONSUL_HTTP_TOKEN" '.Job.ConsulToken = $token' < ${json} \
  | curl -f \
    -X POST \
    -H "X-Nomad-Token: $NOMAD_TOKEN" \
    -H "X-Vault-Token: $(vault print token)" \
    -d @- \
    "$NOMAD_ADDR/v1/jobs"
''
