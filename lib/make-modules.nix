{lib}: dir: let
  join = a: b:
    if a == ""
    then b
    else "${a}-${b}";

  convert = prefix: d: let
    entries = builtins.readDir d;
    expanded = builtins.mapAttrs (name: type:
      if (type == "regular") && (lib.strings.hasSuffix ".nix" name)
      then [
        (join prefix name)
        (d + "/${name}")
      ]
      else if type == "directory"
      then [
        (join prefix name)
        (convert (join prefix name) (d + "/${name}"))
      ]
      else null)
    entries;
  in
    builtins.filter (a: a != null) (builtins.attrValues expanded);

  tree = convert "" dir;

  result = builtins.foldl' (s: elems: let
    cat = builtins.elemAt elems 0;
    car = builtins.elemAt elems 1;
  in
    if builtins.typeOf car == "list"
    then (result s car)
    else
      s
      ++ [
        {
          name = builtins.substring 0 ((builtins.stringLength cat) - 4) cat;
          value = car;
        }
      ]);

  folded = builtins.listToAttrs (result [] tree);
  modules = builtins.mapAttrs (_: v: {config, ...}: {imports = [v];}) folded;
in
  modules
