{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption;
  inherit (lib.types) str enum submodule attrsOf nullOr;
  inherit (config.cluster) kms;

  installType = submodule {
    options = {
      script = mkOption {
        type = str;
        default = "";
      };
      source = mkOption { type = nullOr str; };
      target = mkOption { type = nullOr str; };
    };
  };

  secretType = submodule {
    options = {
      generate = lib.mkOption { type = attrsOf str; };
      install = lib.mkOption { type = attrsOf installType; };

      generateScript = lib.mkOption {
        type = str;
        apply = f:
          let
            scripts = lib.concatStringsSep "\n" (lib.mapAttrsToList
              (name: value:
                let
                  script = pkgs.writeShellScriptBin name ''
                    ## ${name}

                    set -exuo pipefail

                    ${value}
                  '';
                in "${script}/bin/${name}") config.secrets.generate);
          in pkgs.writeShellScriptBin "generate-secrets" ''
            set -exuo pipefail
            mkdir -p secrets encrypted
            ${scripts}
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

  config = {
    services = lib.flip lib.mapAttrs' config.secrets.install (name: cfg:
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
        };
        path = with pkgs; [ sops coreutils ];
        script = ''
          set -euxo pipefail

          ${lib.optionalString (cfg.target != null && cfg.source != null) ''
            target="${toString cfg.target}"
            mkdir -p "$(dirname "$target")"
            sops --decrypt --input-type json ${cfg.source} > "$target.new"
            test -s "$target.new"
            mv "$target.new" "$target"
          ''}

          ${cfg.script}
        '';
      });
  };
}
