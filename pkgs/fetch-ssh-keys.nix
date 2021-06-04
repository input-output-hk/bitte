{ lib, writeBashBinChecked, curl, jq, gnugrep, gawk, remarshal, ... }:
let
  extraConfig = builtins.toJSON {
    paths = [{
      glob = "secrets/*";
      groups = [ "devops" ];
    }];
  };
in writeBashBinChecked "fetch-ssh-keys" ''
  export PATH="${lib.makeBinPath [ curl jq gnugrep gawk remarshal ]}"

  set -euo pipefail

  token="$(awk '/github.com/ {print $6;exit}' ~/.netrc)"

  # get members of the devops team in input-output-hk org

  mapfile -t members < <(
    curl https://api.github.com/organizations/12909177/team/2333149/members \
      -s \
      -u "manveru:$token" \
      -H 'Accept: application/vnd.github.v3+json' \
      | jq -e -r '.[].login' \
      | grep -v iohk-devops
  )

  keyfile="{}"

  for name in "''${members[@]}"; do
    echo "fetching keys for $name..."
    readarray -t keys < <(curl -s "https://github.com/$name.keys")

    for key in "''${keys[@]}" ; do
      echo "adding $key"
      keyfile=$(
        echo "$keyfile" \
        | jq -e -S \
          --arg name "$name" \
          --arg key "$key" \
          '.groups[$name] += [$key]')
    done
  done

  keyfile="$(
    echo "$keyfile" \
    | jq '.groups.devops = (.groups | keys)'
  )"

  final="$(jq -s '.[0] * .[1]' <(echo "$keyfile") <(echo ${extraConfig}))"

  echo "$keyfile" | remarshal -if json -of toml > .agenix.toml
''
