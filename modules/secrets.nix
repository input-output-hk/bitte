{ lib, config, pkgs, ... }:
let
  inherit (config.cluster) kms;

  installType = with lib.types; submodule {
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

  secretType = with lib.types; submodule {
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
            scripts = lib.concatStringsSep "\n" (lib.mapAttrsToList
              (name: value:
                let
                  script = pkgs.writeShellScriptBin name ''
                    ## ${name}

                    set -euo pipefail

                    ${value}
                  '';
                in "${script}/bin/${name}") config.secrets.generate);
          in pkgs.writeShellScriptBin "generate-secrets" ''
            set -euo pipefail

            export PATH="$PATH:${
              lib.makeBinPath (with pkgs; [ utillinux git ])
            }"

            mkdir -p secrets encrypted

            echo "aquiring secrets/generate.lock ..."

            exec 100>secrets/generate.lock || exit 1
            flock -n 100 || (
              echo "secrets/generate.lock exists, not generating secrets!"
              exit
            )
            trap 'rm -f secrets/generate.lock' EXIT

            ${scripts}
            git add encrypted/
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

  config.assertions = lib.flip lib.mapAttrsToList config.secrets.install
    (name: cfg: {
      assertion = cfg.source == null || builtins.pathExists cfg.source;
      message = ''secrets: source path "${cfg.source}" must exist.'';
    });

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
