{ config, lib, ... }:

with lib;
with types;

let
  cfg = config.services.hydra;

  projectType = submodule ({ name, ... }: {
    options = {
      id = mkOption {
        type = str;
        default = name;
      };

      enable = mkOption {
        type = bool;
        default = true;
        apply = v: toString (if v then 1 else 0);
      };

      hidden = mkOption {
        type = bool;
        default = false;
        apply = v: toString (if v then 1 else 0);
      };

      displayName = mkOption {
        type = str;
        default = name;
      };

      homepage = mkOption {
        type = str;
        default = "https://github.com/input-output-hk/${name}";
      };

      owner = mkOption {
        type = enum (lib.attrNames config.services.hydra.users);
      };

      declfile = mkOption {
        type = str;
        default = "jobsets/${name}.json";
      };

      decltype = mkOption {
        type = str;
        default = "git";
      };

      declvalue = mkOption {
        type = str;
      };

      description = mkOption {
        type = str;
        default = "";
      };
    };
  });

  userType = submodule ({ name, ... }: {
    options = {
      id = mkOption {
        type = str;
        default = name;
      };

      fullName = mkOption {
        type = str;
        default = name;
      };

      email = mkOption {
        type = str;
        default = name;
      };

      emailOnError = mkOption {
        type = bool;
        default = true;
        apply = v: toString (if v then 1 else 0);
      };

      publicDashboard = mkOption {
        type = bool;
        default = false;
        apply = v: if v then "t" else "f";
      };

      roles = mkOption {
        type = listOf (enum [
          "admin"
          "create-projects"
          "restart-jobs"
          "bump-to-front"
          "cancel-build"
        ]);
        default = [];
      };
    };
  });

in {
  options.services.hydra = {
    users = mkOption {
      type = attrsOf userType;
      default = {};
    };

    projects = mkOption {
      type = attrsOf projectType;
      default = {};
    };
  };
}
