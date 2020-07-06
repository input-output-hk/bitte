{ lib, writeShellScriptBin, sops, coreutils, jq, gnugrep }:
writeShellScriptBin "sops-add-file" ''
  export PATH=${lib.makeBinPath [ sops coreutils jq gnugrep ]}

  set -exuo pipefail

  file="$1"
  key="$2"
  secrets="$3"
  value="$(jq -R -s -c < "$file")"

  [ -s "$secrets" ] || echo '{}' > "$secrets"
  grep sops "$secrets" || sops -i -e "$secrets" # --set only works on initialized files
  sops -i -e --set "$key $value" "$secrets"
  sops -d "$secrets"
''
