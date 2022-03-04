{ lib, config, pkgs, ... }:
let

  installType = with lib.types;
    submodule {
      options = {
        script = lib.mkOption {
          type = with lib.types; str;
          default = "";
        };

        source = lib.mkOption {
          type = with lib.types; nullOr path;
          default = null;
        };

        target = lib.mkOption {
          type = with lib.types; nullOr path;
          default = null;
        };

        inputType = lib.mkOption {
          type = with lib.types; enum [ "json" "yaml" "dotenv" "binary" ];
          default = "json";
        };

        outputType = lib.mkOption {
          type = with lib.types; enum [ "json" "yaml" "dotenv" "binary" ];
          default = "json";
        };
      };
    };

  secretType = with lib.types;
    submodule {
      options = {
        encryptedRoot = lib.mkOption { type = with lib.types; path; };

        generate = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = { };
        };

        install = lib.mkOption {
          type = with lib.types; attrsOf installType;
          default = { };
        };

        generateScript = lib.mkOption {
          type = with lib.types; str;
          apply = f:
            let
              relEncryptedFolder = lib.last (builtins.split "-" (toString config.secrets.encryptedRoot));
              scripts = lib.concatStringsSep "\n" (lib.mapAttrsToList
                (name: value:
                  let
                    script = pkgs.writeBashBinChecked name ''
                      ## ${name}

                      set -euo pipefail

                      ${value}
                    '';
                  in "${script}/bin/${name}") config.secrets.generate);
            in pkgs.writeBashBinChecked "generate-secrets" ''
              export PATH="$PATH:${
                lib.makeBinPath (with pkgs; [ utillinux git ])
              }"

              (flock -w 30 9 || exit 1
                mkdir -p secrets ${relEncryptedFolder}

                ${scripts}

                git add ${relEncryptedFolder}/
              ) 9>.secrets-generate.lock
            '';
        };
      };
    };
in {
  options = {
    secrets = lib.mkOption {
      default = { };
      type = with lib.types; secretType;
    };
  };

  config.systemd.services = lib.flip lib.mapAttrs' config.secrets.install
    (name: cfg:
      lib.nameValuePair "secret-${name}" {
        wantedBy = [
          "multi-user.target"
          "consul.service"
          "vault.service"
          "nomad.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "30s";
          WorkingDirectory = "/run/keys";
        };

        path = with pkgs; [ sops coreutils ];

        script = ''
          set -euxo pipefail

          ${lib.optionalString (cfg.target != null && cfg.source != null) ''
            target="${toString cfg.target}"
            mkdir -p "$(dirname "$target")"
            sops --decrypt --input-type ${cfg.inputType} --output-type ${cfg.outputType} ${cfg.source} > "$target.new"
            test -s "$target.new"
            mv "$target.new" "$target"
          ''}

          ${cfg.script}
        '';
      });
}
