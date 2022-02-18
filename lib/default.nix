{ lib, inputs }:
let
  inherit (inputs) nixpkgs deploy;
  bitte = inputs.self;
in rec {
  terralib = import ./terralib.nix { inherit lib nixpkgs; };

  warningsModule = import ./warnings.nix;

  recImport = import ./rec-import.nix { inherit lib; };
  sanitize = import ./sanitize.nix { inherit lib snakeCase; };
  snakeCase = import ./snake-case.nix { inherit lib; };
  mkModules = import ./make-modules.nix { inherit lib; };

  mkCluster = import ./clusters.nix { inherit mkSystem lib; };
  mkBitteStack =
    import ./mk-bitte-stack.nix { inherit mkCluster mkDeploy lib nixpkgs bitte; };
  mkDeploy = import ./mk-deploy.nix { inherit deploy lib; };
  mkSystem = import ./mk-system.nix { inherit nixpkgs bitte; };

  ensureDependencies = import ./ensure-dependencies.nix { inherit lib; };
}

