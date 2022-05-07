{ lib, inputs }:
let
  inherit (inputs) nixpkgs deploy;
  bitte = inputs.self;
in rec {
  terralib = import ./terralib.nix { inherit lib nixpkgs; };

  warningsModule = import ./warnings.nix;

  recImport = import ./rec-import.nix { inherit lib; };
  sanitize = import ./sanitize.nix { inherit lib snakeCase; };
  kv = import ./kv.nix { inherit lib terralib; };
  snakeCase = import ./snake-case.nix { inherit lib; };
  mkModules = import ./make-modules.nix { inherit lib; };

  mkCluster = import ./clusters.nix { inherit mkSystem lib; };
  mkBitteStack =
    import ./mk-bitte-stack.nix { inherit mkCluster mkDeploy lib nixpkgs bitte; };
  mkDeploy = import ./mk-deploy.nix { inherit deploy lib; };
  mkSystem = import ./mk-system.nix { inherit nixpkgs bitte; };
  mkVaultResources = kv.mkVaultResources;
  mkConsulResources = kv.mkConsulResources;

  net = import ./net.nix { inherit lib; };

  securityGroupRules = import ./security-group-rules.nix { inherit terralib lib; };

  ensureDependencies = import ./ensure-dependencies.nix { inherit lib; };
  mkNomadHostVolumesConfig = import ./mk-nomad-host-volumes-config.nix { inherit lib; };

  augmentNomadJob = import ./augment-nomad-job.nix { inherit nixpkgs; };
  mkNomadJobs = ns: envs: let
    pkgs = import nixpkgs { system = "x86_64-linux";};
  in
    builtins.mapAttrs (n: job:
    let
      rendered = pkgs.writeText "${n}.${ns}.nomad.json"
        (builtins.toJSON { job = augmentNomadJob job.job; });
    in
      pkgs.linkFarm "job.${n}.${ns}" [
        { name = "job"; path = rendered; }
      ]
    ) envs.${ns};
}

