{ lib, inputs }: rec {
  recImport = import ./rec-import.nix { inherit lib; };
  sanitize = import ./sanitize.nix { inherit lib snakeCase; };
  snakeCase = import ./snake-case.nix { inherit lib; };
  mkModules = import ./make-modules.nix { inherit lib; };
  mkHashiStack = import ./mk-hashi-stack.nix;
  mkDeploy = import ./mk-deploy.nix {
    inherit (inputs) deploy;
    inherit lib;
  };
}

