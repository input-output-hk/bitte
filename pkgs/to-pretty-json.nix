{
  writeText,
  runCommandNoCCLocal,
  jq,
}: name: value: let
  json = builtins.toJSON value;
  mini = writeText "${name}.mini.json" json;
in
  runCommandNoCCLocal "${name}.json" {} ''
    ${jq}/bin/jq -S < ${mini} > $out
  ''
