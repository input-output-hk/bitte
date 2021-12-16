{ lib, inputs }:
let
  inherit (inputs) nixpkgs deploy;
  bitte = inputs.self;
in rec {
  terralib = import ./terralib.nix { inherit lib nixpkgs; };

  recImport = import ./rec-import.nix { inherit lib; };
  sanitize = import ./sanitize.nix { inherit lib snakeCase; };
  snakeCase = import ./snake-case.nix { inherit lib; };
  mkModules = import ./make-modules.nix { inherit lib; };

  mkCluster = import ./clusters.nix { inherit mkSystem lib; };
  mkBitteStack =
    import ./mk-bitte-stack.nix { inherit mkCluster mkDeploy lib; };
  mkDeploy = import ./mk-deploy.nix { inherit deploy lib; };
  mkSystem = import ./mk-system.nix { inherit nixpkgs bitte; };

  ensureDependencies = import ./ensure-dependencies.nix { inherit lib; };

  mkHashiStack = { flake, domain, dockerRegistry ? "docker." + domain
    , dockerRole ? "developer"
    , vaultDockerPasswordKey ? "kv/nomad-cluster/docker-developer-password" }:
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
        Note: You won't be able to use `bitte deploy` since it requires to pass
        a deploy ssh key to mkBitteStack, directly.
      '' mkBitteStack {
        self = flake;
        pkgs =
          flake.inputs.nixpkgs.legacyPackages.x86_64-linux.extend flake.overlay;
        deploySshKey =
          "fake"; # we can't infer this, please change to mkBitteStack
        inherit (flake) inputs;
        inherit domain;
        inherit dockerRegistry;
        jobs = flake + "/jobs";
        docker = flake + "/docker";
        clusters = flake + "/clusters";
      };
}

