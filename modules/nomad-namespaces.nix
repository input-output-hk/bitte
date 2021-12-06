{ lib, pkgs, config, pkiFiles, ... }:
let cfg = config.services.nomad.namespaces;
in {
  options = {
    services.nomad.namespaces = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            default = name;
          };

          quota = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };

          description = lib.mkOption { type = lib.types.str; };
        };
      }));

      default = { };
    };

    services.nomad-namespaces.enable =
      lib.mkEnableOption "Maintain Nomad namespaces";
  };

  config = {
    services.nomad.namespaces.default =
      lib.mkDefault { description = "Default shared namespace"; };

    systemd.services.nomad-namespaces =
      lib.mkIf config.services.nomad-namespaces.enable {
        after = [ "nomad.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10s";
          ExecStartPre = pkgs.writeShellScript "check" ''
            ${pkgs.systemd}/bin/systemctl is-active nomad.service
          '';
        };

        environment = {
          inherit (config.environment.variables) NOMAD_ADDR;
          CURL_CA_BUNDLE = pkiFiles.caCertFile;
        };

        path = with pkgs; [ nomad jq ];

        script = ''
          set -euo pipefail

          NOMAD_TOKEN="$(< /var/lib/nomad/bootstrap.token)"
          export NOMAD_TOKEN

          set -x

          ${lib.concatStringsSep "" (lib.mapAttrsToList (name: value: ''
            nomad namespace apply -description ${
              lib.escapeShellArg value.description
            } "${name}" \
            ${lib.optionalString (value.quota != null)
            "-quota ${lib.escapeShellArg value.quota}"}
          '') cfg)}

            keepNames=(${toString (builtins.attrNames cfg)})

            namespaces=($(nomad namespace list -json | jq -e -r '.[].Name'))

            for name in "''${namespaces[@]}"; do
              keep=""
              for kname in "''${keepNames[@]}"; do
                if [ "$name" = "$kname" ]; then
                  keep="yes"
                fi
              done

              if [ -z "$keep" ]; then
                nomad namespace delete "$name"
              fi
            done
        '';
      };
  };
}
