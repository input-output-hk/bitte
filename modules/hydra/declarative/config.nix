{ config, pkgs, lib, ... }:

let cfg = config.services.hydra;

in with lib; {
  config = mkIf cfg.enable {
    systemd.services.hydra-declarative = {
      description = "Hydra declarative projects and users";
      wantedBy = [ "multi-user.target" ];
      requires = [ "hydra-init.service" "postgresql.service" ];
      after = [ "hydra-init.service" "postgresql.service" ];

      path = [ config.services.postgresql.package ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "hydra";
      };

      script = ''
        cat <<EOF | psql
        BEGIN;

        DELETE FROM users WHERE username not in (${
          lib.concatMapStringsSep "," (username: "'${username}'")
          (builtins.attrNames cfg.users)
        });
        DELETE FROM userroles;
        UPDATE projects SET enabled = 0;

        ${lib.concatMapStringsSep "\n" (username:
          with cfg.users.${username};
          let
            cols =
              "(username,fullname,emailaddress,password,emailonerror,type,publicdashboard)";
            vals =
              "('${email}','${fullName}','${email}','!',${emailOnError},'google','${publicDashboard}')";
          in ''
            INSERT INTO users ${cols} VALUES ${vals} ON CONFLICT (username) DO UPDATE SET ${cols} = ${vals};

            ${lib.concatMapStringsSep "\n" (role: ''
              INSERT INTO userroles (username,role) VALUES ('${username}','${role}');
            '') roles}
          '') (builtins.attrNames cfg.users)}

        ${lib.concatMapStringsSep "\n" (projectName:
          with cfg.projects.${projectName};
          let
            cols =
              "(name,declfile,decltype,declvalue,displayname,description,homepage,owner,enabled,hidden)";
            vals =
              "('${projectName}','${declfile}','${decltype}','${declvalue}','${displayName}','${description}','${homepage}','${owner}',${enable},${hidden})";
          in ''
            INSERT INTO projects ${cols} VALUES ${vals} ON CONFLICT (name) DO UPDATE SET ${cols} = ${vals};
          '') (builtins.attrNames cfg.projects)}

        COMMIT;
        EOF
      '';
    };
  };
}
