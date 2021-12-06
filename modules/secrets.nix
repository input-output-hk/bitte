{ lib, config, pkgs, ... }:
let
  inherit (lib.types) str enum submodule attrsOf nullOr path;
  inherit (config.cluster) kms;

  installType = submodule {
    options = {
      script = lib.mkOption {
        type = str;
        default = "";
      };

      source = lib.mkOption {
        type = nullOr path;
        default = null;
      };

      target = lib.mkOption {
        type = nullOr path;
        default = null;
      };

      inputType = lib.mkOption {
        type = enum [ "json" "yaml" "dotenv" "binary" ];
        default = "json";
      };

      outputType = lib.mkOption {
        type = enum [ "json" "yaml" "dotenv" "binary" ];
        default = "json";
      };
    };
  };

  secretType = submodule {
    options = {
      encryptedRoot = lib.mkOption { type = path; };

      generate = lib.mkOption {
        type = attrsOf str;
        default = { };
      };

      install = lib.mkOption {
        type = attrsOf installType;
        default = { };
      };

      generateScript = lib.mkOption {
        type = str;
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
            export PATH="$PATH:${
              lib.makeBinPath (with pkgs; [ utillinux git ])
            }"
            [ "$FLOCKER" != "$0" ] && exec env FLOCKER="$0" flock -en "$0" "$0" $@ ||
            set -euo pipefail

            mkdir -p secrets encrypted

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
      type = secretType;
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
