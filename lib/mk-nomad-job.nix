{ writeText, lib, pkgs, toPrettyJSON, callPackage }:
name: configuration:
let
  inherit (builtins) length mapAttrs attrNames typeOf;
  inherit (lib) flip const evalModules getAttrs remove pipe mapAttrs';

  pp = v: __trace (__toJSON v) v;

  # TODO: fix properly
  specialUpper = {
    id = "ID";
    serverAddress = "server_address";
    server_address = "server_address";
    protocol = "protocol";
    auth = "auth";
    image = "image";
    volumes = "volumes";
    args="args";
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
    if set ? command then set else mapAttrs' capitalize set;

  dbg = input:
    if true then
      if (lib.traceSeqN 1 (__attrNames input) input) ? description then
        lib.traceSeqN 1 (__typeOf input.type) input
      else
        input
    else
      input;

  sanitize = value:
    let
      type = typeOf value;
      sanitized = if type == "list" then
        map sanitize value
      else if type == null then
        null
      else if type == "set" then
        pipe (attrNames value) [
          (remove "_ref")
          (remove "_module")
          (flip getAttrs value)
          capitalizeAttrs
          (mapAttrs (const sanitize))
        ]
      else
        value;
    in sanitized;

  evaluateConfiguration = configuration:
    evalModules {
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
