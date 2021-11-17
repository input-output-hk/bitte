{ lib, inputs }: let
  inherit (inputs) nixpkgs deploy;
  bitte = inputs.self;
in rec {
  terralib = import ./terralib.nix { inherit lib nixpkgs; };

  recImport = import ./rec-import.nix { inherit lib; };
  sanitize = import ./sanitize.nix { inherit lib snakeCase; };
  snakeCase = import ./snake-case.nix { inherit lib; };
  mkModules = import ./make-modules.nix { inherit lib; };

  mkCluster = import ./clusters.nix { inherit mkSystem mkJob lib; };
  mkBitteStack = import ./mk-bitte-stack.nix { inherit mkCluster lib; };
  mkDeploy = import ./mk-deploy.nix { inherit deploy lib; };
  mkSystem = import ./mk-system.nix { inherit nixpkgs bitte; };
  mkJob = import ./mk-job.nix;

  mkHashiStack =
    { flake
    , domain
    , dockerRegistry ? "docker." + domain, dockerRole ? "developer"
    , vaultDockerPasswordKey ? "kv/nomad-cluster/docker-developer-password"
    }:
    if (flake.inputs ? terranix) then
      lib.warn ''
      mkHashiStack will be deprecated shortly, please use mkBitteStack direcly.
      See: bitte/lib/default.nix
      -> The confusing terranix inputs indirection has been cleaned up, as well.
      ''
    else
      lib.warn ''
      mkHashiStack will be deprecated shortly, please use mkBitteStack direcly.
      See: bitte/lib/default.nix
      ''
    mkBitteStack {
      self = flake;
      pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux.extend flake.overlay;
      inherit (flake) inputs;
      inherit domain;
      inherit dockerRegistry vaultDockerPasswordKey;
      jobs = flake + "/jobs";
      docker = flake + "/docker";
      clusters = flake + "/clusters";
    };
}

