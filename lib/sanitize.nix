{
  lib,
  snakeCase,
}: let
  sanitize = obj:
    lib.getAttr (builtins.typeOf obj) {
      lambda = throw "Cannot sanitize functions";
      bool = obj;
      int = obj;
      float = obj;
      string = obj;
      path = toString obj;
      list = map sanitize obj;
      inherit null;
      set =
        if (lib.length (lib.attrNames obj) == 0)
        then null
        else
          lib.pipe obj [
            (lib.filterAttrs
              (name: value: name != "_module" && name != "_ref" && value != null))
            (lib.mapAttrs' (name: value: lib.nameValuePair name (sanitize value)))
          ];
    };
in
  sanitize
