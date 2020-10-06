{ writeShellScriptBin }:
writeShellScriptBin "bitte-tokens" ''
  set -euo pipefail

  vault token lookup "$(vault print token)" &> /dev/null \
  || vault login -method github -path github-employees -no-print

  aws s3 ls &> /dev/null \
  || (
    creds="$(vault read -format json aws/creds/developer)"
    aws configure set --profile mantis aws_access_key_id "$( echo "$creds" | jq -r -e .data.access_key )"
    aws configure set --profile mantis aws_secret_access_key "$(echo "$creds" | jq -r -e .data.secret_key)"
  )

  NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/developer)"
  export NOMAD_TOKEN

  CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/developer)"
  export CONSUL_HTTP_TOKEN
''
