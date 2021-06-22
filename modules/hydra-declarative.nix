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
        type = enum (attrNames config.services.hydra.users);
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

  config = mkIf cfg.enable {
    systemd.services.hydra-declarative = {
      description = "Hydra declarative projects and users";
      wantedBy    = [ "multi-user.target" ];
      requires    = [ "hydra-init.service" "postgresql.service" ];
      after       = [ "hydra-init.service" "postgresql.service" ];

      path = [ config.services.postgresql.package ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "hydra";
      };

      script = ''
        cat <<EOF | psql
        BEGIN;

        DELETE FROM users WHERE username not in (${concatMapStringsSep "," (username: "'${username}'") (attrNames cfg.users)});
        DELETE FROM userroles;
        UPDATE projects SET enabled = 0;

        ${concatMapStringsSep "\n" (username: with cfg.users.${username}; let
          cols = "(username,fullname,emailaddress,password,emailonerror,type,publicdashboard)";
          vals = "('${email}','${fullName}','${email}','!',${emailOnError},'google','${publicDashboard}')";
        in  ''
          INSERT INTO users ${cols} VALUES ${vals} ON CONFLICT (username) DO UPDATE SET ${cols} = ${vals};

          ${concatMapStringsSep "\n" (role: ''
            INSERT INTO userroles (username,role) VALUES ('${username}','${role}');
          '') roles}
        '') (attrNames cfg.users)}

        ${concatMapStringsSep "\n" (projectName: with cfg.projects.${projectName}; let
          cols = "(name,declfile,decltype,declvalue,displayname,description,homepage,owner,enabled,hidden)";
          vals = "('${projectName}','${declfile}','${decltype}','${declvalue}','${displayName}','${description}','${homepage}','${owner}',${enable},${hidden})";
        in  ''
          INSERT INTO projects ${cols} VALUES ${vals} ON CONFLICT (name) DO UPDATE SET ${cols} = ${vals};
        '') (attrNames cfg.projects)}

        COMMIT;
        EOF
      '';
    };
  };
}
