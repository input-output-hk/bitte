{ lib }:
dir:

let
  join = a: b: if a == "" then b else "${a}-${b}";

  inherit (builtins)
    readDir mapAttrs attrValues foldl' elemAt typeOf substring stringLength
    listToAttrs filter;

  convert = prefix: d:
    let
      entries = readDir d;
      expanded = mapAttrs (name: type:
        if (type == "regular") && (lib.strings.hasSuffix ".nix" name) then [
          (join prefix name)
          (d + "/${name}")
        ] else if type == "directory" then [
          (join prefix name)
          (convert (join prefix name) (d + "/${name}"))
        ] else
          null) entries;
    in filter (a: a != null) (attrValues expanded);

  tree = convert "" dir;

  result = foldl' (s: elems:
    let
      cat = elemAt elems 0;
      car = elemAt elems 1;
    in if typeOf car == "list" then
      (result s car)
    else
      s ++ [{
        name = substring 0 ((stringLength cat) - 4) cat;
        value = car;
      }]);

  folded = result [ ] tree;
in listToAttrs folded
