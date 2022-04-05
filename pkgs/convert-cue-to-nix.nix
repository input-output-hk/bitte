{ lib
, alejandra
, cue
, iogo
, gnused
, hcl2json
, jq
, writeShellScriptBin
}:

writeShellScriptBin "convert-cue-to-nix.sh" ''
  set -euo pipefail

  export PATH=${lib.makeBinPath [ alejandra cue iogo gnused hcl2json jq]}

  namespaces=($(cue export | jq -r '.rendered | keys[]'))
  pwd="$(pwd)"

  for ns in ''${namespaces[@]}; do
    jobs=($(cue export | jq -r ".rendered[\"$ns\"] | keys[]"))
    mkdir -p $ns
    pushd $ns
    for job in ''${jobs[@]}; do
      mkdir -p "$job"
      pushd $job
      # hcl2json will wrap each block in an array, these are mostly extraneous
      echo "$(cd $pwd && iogo render --namespace $ns $job |
        hcl2json -simplify - |
        jq '.job.'$job' = .job.'$job'[]')" > default.json
      nix eval --impure --expr "builtins.fromJSON (builtins.readFile ./default.json)" >"default.nix"
      alejandra default.nix
      sed -i -e 's|\[{}\]|{}|g' default.nix
      popd
    done
    popd
  done
''
