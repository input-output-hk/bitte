{ name, json, writeShellScriptBin }:
writeShellScriptBin "nomad-run" ''
  echo running ${json}

  set -xeuo pipefail

  vault login -method aws -no-print

  NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/admin)"
  export NOMAD_TOKEN

  CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/admin)"
  export CONSUL_HTTP_TOKEN

  bucket="$(nix eval ".#clusters.$BITTE_CLUSTER.proto.config.cluster.s3Bucket" --raw)"
  region="$(nix eval ".#clusters.$BITTE_CLUSTER.proto.config.cluster.region" --raw)"

  nix copy --to "s3://''${bucket}/infra/binary-cache/?region=''${region}&secret-key=secrets/nix-secret-key-file" ${json}

  jq --arg token "$CONSUL_HTTP_TOKEN" '.Job.ConsulToken = $token' < ${json} \
  | curl -f \
      -X POST \
      -H "X-Nomad-Token: $NOMAD_TOKEN" \
      -d @- \
      "$NOMAD_ADDR/v1/jobs"
''
