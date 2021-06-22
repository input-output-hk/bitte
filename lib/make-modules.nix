{ lib }: dir:

let
  join = a: b: if a == "" then b else "${a}-${b}";

  inherit (builtins) readDir mapAttrs attrValues foldl' elemAt typeOf substring stringLength listToAttrs;

  convert = prefix: d:
    let
      entries = readDir d;
      filterNix = lib.filterAttrs (n: v: lib.strings.hasSuffix ".nix" n);
      expanded = mapAttrs (name: type:
        if type == "regular" then [
          (join prefix name)
          (d + "/${name}")
        ] else if type == "directory" then [
          (join prefix name)
          (convert (join prefix name) (d + "/${name}"))
        ] else
          null) (filterNix entries);
    in attrValues expanded;

  tree = convert "" dir;

  result = sum: input:
    foldl' (s: elems:
      let
        cat = elemAt elems 0;
        car = elemAt elems 1;
      in if typeOf car == "list" then
        (result s car)
      else
        s ++ [{
          name = substring 0 ((stringLength cat) - 4) cat;
          value = import car;
        }]) sum input;

  folded = result [ ] tree;
in listToAttrs folded
