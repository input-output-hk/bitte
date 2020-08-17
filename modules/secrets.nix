{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption;
  inherit (lib.types) str enum submodule attrsOf;
  inherit (config.cluster) kms;

  secretType = submodule {
    options = {
      generate = lib.mkOption { type = attrsOf str; };
      install = lib.mkOption { type = attrsOf str; };
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
}
