{ writeText, lib, pkgs, toPrettyJSON, callPackage }:
name: configuration:
let
  # FIXME: not sure where those were used anymore... add them to specialUpper
  # when you encounter them again.
  exceptions = {
    serverAddress = "server_address";
    server_address = "server_address";
    protocol = "protocol";
  };

  specialUpper = parents: name:
    let path = parents ++ [ name ];
    in if parents == [ "TaskGroups" "Volumes" ] then
      name
    else if path == [ "id" ] then
      "ID"
    else if path == [ "TaskGroups" "Tasks" "Resources" "memoryMB" ] then
      "MemoryMB"
      # Task config has to be passed verbatim to the driver.
    else if (lib.take 3 parents) == [ "TaskGroups" "Tasks" "Config" ] then
      name
    else
      null;

  capitalizeString = parents: name:
    let special = specialUpper parents name;
    in if special != null then
      special
    else
      ((lib.toUpper (lib.substring 0 1 name))
        + (lib.substring 1 (lib.stringLength name) name));

  capitalize = parents: name: value: {
    name = capitalizeString parents name;
    value = value;
  };

  capitalizeAttrs = parents: set:
    if set ? command then set else lib.mapAttrs' (capitalize parents) set;

  sanitize = parents: value:
    let
      type = builtins.typeOf value;
      sanitized = if type == "list" then
        map (sanitize parents) value
      else if type == null then
        null
      else if type == "set" then
        lib.pipe (builtins.attrNames value) [
          (lib.remove "_ref")
          (lib.remove "_module")
          (lib.flip lib.getAttrs value)
          (capitalizeAttrs parents)
          (builtins.mapAttrs (k: v: sanitize (parents ++ [ k ]) v))
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
    in sanitize [ ] evaluated.config;

  evaluated = { Job = nomadix configuration; };

  dockerImages = lib.pipe evaluated.Job.TaskGroups [
    (map (x: x.Tasks))
    builtins.concatLists
    (map (y:
      if y.Driver == "docker" then {
        name = builtins.unsafeDiscardStringContext y.Config.image;
        value = y.Config.image.image;
      } else
        null))
    (lib.filter (value: value != null))
    builtins.listToAttrs
  ];

  json = toPrettyJSON name evaluated;

  run = callPackage ./run-nomad-job.nix { inherit json name dockerImages; };
in { inherit json evaluated run dockerImages; }
