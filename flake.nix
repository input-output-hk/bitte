{
  description = "Flake containing Bitte clusters";
  inputs.std.url = "github:divnix/std";
  inputs.flake-arch.url = "github:johnalotoski/flake-arch";
  inputs.n2c.url = "github:nlewo/nix2container";
  inputs.data-merge.url = "github:divnix/data-merge";
  inputs.capsules.url = "github:input-output-hk/devshell-capsules";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    nixpkgs-docker.url = "github:nixos/nixpkgs/ff691ed9ba21528c1b4e034f36a04027e4522c58";
    nixpkgs-terraform.url = "github:NixOS/nixpkgs/8b3398bc7587ebb79f93dfeea1b8c574d3c6dba1";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nix.url = "github:nixos/nix/2.17-maintenance";
    agenix.url = "github:ryantm/agenix";
    agenix-cli.url = "github:cole-h/agenix-cli";
    ragenix.url = "github:yaxitech/ragenix";
    deploy.url = "github:input-output-hk/deploy-rs";

    terranix.url = "github:terranix/terranix";
    terranix.inputs.nixpkgs.follows = "blank";

    utils.url = "github:numtide/flake-utils";
    blank.url = "github:divnix/blank";

    # Vector >= 0.20.0 versions require nomad-follower watch-config format fix
    nomad-follower.url = "github:input-output-hk/nomad-follower";

    fenix.url = "github:nix-community/fenix";

    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
  };

  outputs = {
    deploy,
    fenix,
    flake-arch,
    nix,
    nixpkgs,
    nixpkgs-terraform,
    nixpkgs-unstable,
    ragenix,
    self,
    utils,
    ...
  } @ inputs:
    inputs.std.growOn {
      inherit inputs;
      inherit (inputs.flake-arch) systems;
      cellsFrom = ./nix;
      cellBlocks = [
        (inputs.std.devshells "devshells")
        (inputs.std.installables "packages")

        # ----------
        # NixOS: Modules, Profiles, Aggregates
        # ----------

        # profile aggregates - combine profiles into classes
        #   "composition over case switches"
        (inputs.std.functions "aggregates")
        # profiles - have side effects; don't define options
        (inputs.std.functions "profiles")
        # modules - have no side effects; define options
        (inputs.std.functions "modules")

        # ----------
        # Terraform: loops
        # ----------

        # loops - reconcile a target state
        (inputs.std.functions "loops")
      ];
    }
    # soil -- TODO: remove soil
    (let
      inherit (inputs.flake-arch) systems;

      overlays = [
        fenix.overlay
        deploy.overlay
        localPkgsOverlay
        terraformProvidersOverlay
        (_: prev: {inherit (self.packages."${prev.system}") bitte;})
      ];

      terraformProvidersOverlay =
        import ./terraform-providers-overlay.nix inputs;

      localPkgsOverlay = import ./overlay.nix inputs;

      pkgsForSystem = system:
        import nixpkgs {
          inherit overlays system;
          config.allowUnfree = true; # for ssm-session-manager-plugin
        };

      unstablePkgsForSystem = system:
        import nixpkgs-unstable {
          inherit overlays system;
        };

      lib = import ./lib {
        inherit (nixpkgs) lib;
        inherit inputs;
      };

      mkChecks = systems: pkgs:
        utils.lib.eachSystem systems (system: {
          checks = builtins.foldl' (acc: pkg: acc // {${pkg} = (pkgsForSystem system).${pkg};}) {} pkgs;
        });
    in
      utils.lib.eachSystem systems
      (
        system: let
          legacyPackages = pkgsForSystem system;
          unstablePackages = unstablePkgsForSystem system;
        in rec {
          inherit legacyPackages;

          packages = {inherit (self.${system}.cli.packages) bitte;};
          packages.default = packages.bitte;
        }
      )
      // {
        inherit lib;
        # eta reduce not possibe since flake check validates for "final" / "prev"
        overlays.default = nixpkgs.lib.composeManyExtensions overlays;
        profiles = lib.mkModules ./profiles;
        nixosModules = lib.mkModules ./modules;
        devshellModule = import ./devshellModule.nix;

        hydraJobs = builtins.mapAttrs (system: v: v // {
          required = inputs.nixpkgs.legacyPackages.${system}.releaseTools.aggregate {
            name = "required";
            constituents = builtins.attrValues v;
          };
        }) (removeAttrs self.checks [
          "aarch64-linux" # not supported on our Hydra instance
        ]);
      }
      // nixpkgs.lib.recursiveUpdate (mkChecks systems [
        "agenix-cli"
        "bitte"
        "bitte-ruby"
        "bundler"
        "caddy"
        "cfssl"
        "consul"
        "cue"
        "docker-distribution"
        "grafana-loki"
        "mill"
        "nomad"
        "nomad-autoscaler"
        "oauth2-proxy"
        "ragenix"
        "scaler-guard"
        "sops"
        "spiffe-helper"
        "spire"
        "spire-agent"
        "spire-server"
        "spire-systemd-attestor"
        "terraform-with-plugins"
        "traefik"
      ])
      (mkChecks ["x86_64-linux"] [
        "agenix"
        "glusterfs"
        "nomad-follower"
        "vault-bin"
        "victoriametrics"
        "vault-backend"
      ]));
}
