{ lib, snakeCase }:
let
  inherit (builtins) typeOf;
  inherit (lib) length attrNames pipe filterAttrs nameValuePair mapAttrs';

  sanitize = obj:
    lib.getAttr (typeOf obj) {
      lambda = throw "Cannot sanitize functions";
      bool = obj;
      int = obj;
      float = obj;
      string = obj;
      path = toString obj;
      list = map sanitize obj;
      null = null;
      set = if (length (attrNames obj) == 0) then
        null
      else
        pipe obj [
          (filterAttrs
            (name: value: name != "_module" && name != "_ref" && value != null))
          (mapAttrs' (name: value: nameValuePair name (sanitize value)))
        ];
    };
in sanitize
