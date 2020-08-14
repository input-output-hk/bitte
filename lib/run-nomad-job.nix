{ name, json, writeShellScriptBin }:
writeShellScriptBin "nomad-run" ''
  echo running ${json}

  curl $NOMAD_ADDR/v1/status/peers

  curl -XPUT -d @${json} http://127.0.0.1/v1/job/${name}
''
