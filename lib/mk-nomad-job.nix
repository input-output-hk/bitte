{ writeText, lib, pkgs, toPrettyJSON, callPackage }:
name: configuration:
let
  # TODO: fix properly
  specialUpper = {
    id = "ID";
    serverAddress = "server_address";
    server_address = "server_address";
    protocol = "protocol";
    auth = "auth";
    image = "image";
    # FIXME: this is used by docker tasks (needs to be lowercase) and by volume mounts (capitalized)...
    # volumes = "volumes";
    args = "args";
    memoryMB = "MemoryMB";
  };

  capitalizeString = s:
    specialUpper.${s} or ((lib.toUpper (lib.substring 0 1 s))
      + (lib.substring 1 (lib.stringLength s) s));

  capitalize = name: value: {
    name = capitalizeString name;
    value = value;
  };

  capitalizeAttrs = set:
    if set ? command then set else lib.mapAttrs' capitalize set;

  sanitize = value:
    let
      type = builtins.typeOf value;
      sanitized = if type == "list" then
        map sanitize value
      else if type == null then
        null
      else if type == "set" then
        lib.pipe (builtins.attrNames value) [
          (lib.remove "_ref")
          (lib.remove "_module")
          (lib.flip lib.getAttrs value)
          capitalizeAttrs
          (builtins.mapAttrs (lib.const sanitize))
        ]
      else
        value;
    in sanitized;

  evaluateConfiguration = configuration:
    lib.evalModules {
      modules = [ { imports = [ ./nomad-job.nix ]; } configuration ];
      specialArgs = { inherit pkgs name; };
    };

  nomadix = configuration:
    let evaluated = evaluateConfiguration configuration;
    in sanitize evaluated.config;

  evaluated = { Job = nomadix configuration; };

  json = toPrettyJSON name evaluated;

  run = callPackage ./run-nomad-job.nix { inherit json name; };
in { inherit json evaluated run; }
