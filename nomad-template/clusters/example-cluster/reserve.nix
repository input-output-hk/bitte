{ lib, config, ... }:
let

  instanceResources = {
    "c5.large" = {
      cpus = 2;
      memory = 4;
    };
    "c5.xlarge" = {
      cpus = 4;
      memory = 8;
    };
    "c5.2xlarge" = {
      cpus = 8;
      memory = 16;
    };
    "c5.4xlarge" = {
      cpus = 16;
      memory = 32;
    };
    "c5.9xlarge" = {
      cpus = 36;
      memory = 72;
    };
    "c5.12xlarge" = {
      cpus = 48;
      memory = 96;
    };
    "c5.18xlarge" = {
      cpus = 72;
      memory = 144;
    };
    "c5.24xlarge" = {
      cpus = 96;
      memory = 192;
    };
    "c5.metal" = {
      cpus = 96;
      memory = 192;
    };
    "c5d.large" = {
      cpus = 2;
      memory = 4;
    };
    "c5d.xlarge" = {
      cpus = 4;
      memory = 8;
    };
    "c5d.2xlarge" = {
      cpus = 8;
      memory = 16;
    };
    "c5d.4xlarge" = {
      cpus = 16;
      memory = 32;
    };
    "c5d.9xlarge" = {
      cpus = 36;
      memory = 72;
    };
    "c5d.12xlarge" = {
      cpus = 48;
      memory = 96;
    };
    "c5d.18xlarge" = {
      cpus = 72;
      memory = 144;
    };
    "c5d.24xlarge" = {
      cpus = 96;
      memory = 192;
    };
    "c5d.metal" = {
      cpus = 96;
      memory = 192;
    };
  };

  resources = instanceResources.${config.asg.instanceType};

  floor = f:
    let
      chars = lib.stringToCharacters (builtins.toJSON f);
      searcher = n: c:
        if n.found then
          n
        else if c == "." then {
          index = n.index;
          found = true;
        } else {
          index = n.index + 1;
          found = false;
        };
      radix = (lib.foldl searcher {
        index = 0;
        found = false;
      } chars).index;
    in builtins.fromJSON (lib.concatStrings (lib.take radix chars));

in {
  config = {
    services.nomad.client = {
      reserved = {
        memory = floor (resources.memory * 1024 * 0.2);
        cpu = floor (resources.cpus * 3600 * 0.2);
      };
    };
  };
}
