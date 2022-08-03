{
  description = "Flake containing Bitte clusters";
  inputs.std.url = "github:divnix/std";
  # 21.11 doesn't yet fullfill all contracts that std consumes
  # inputs.std.inputs.nixpkgs.follows = "nixpkgs";
  inputs.n2c.url = "github:nlewo/nix2container";
  inputs.data-merge.url = "github:divnix/data-merge";
  inputs.capsules.url = "github:input-output-hk/devshell-capsules";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.11";
    nixpkgs-docker.url = "github:nixos/nixpkgs/ff691ed9ba21528c1b4e034f36a04027e4522c58";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nix.url = "github:nixos/nix/2.8.1";
    agenix.url = "github:ryantm/agenix";
    agenix-cli.url = "github:cole-h/agenix-cli";
    ragenix.url = "github:yaxitech/ragenix";
    deploy.url = "github:input-output-hk/deploy-rs";

    terranix.url = "github:terranix/terranix";
    terranix.inputs.nixpkgs.follows = "blank";

    utils.url = "github:numtide/flake-utils";
    blank.url = "github:divnix/blank";

    # Cicero related
    tullia = {
      url = "github:input-output-hk/tullia";
      inputs = {
        # Tullia has nixpkgs 22.05 dependencies (ex: stdenv:shellDryRun)
        nixpkgs.follows = "nixpkgs-unstable";
      };
    };
    # Vector >= 0.20.0 versions require nomad-follower watch-config format fix
    nomad-follower.url = "github:input-output-hk/nomad-follower";

    nomad-driver-nix.url = "github:input-output-hk/nomad-driver-nix";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };

    # Preserved for special use case hydra deployment
    hydra = {
      url = "github:kreisys/hydra/hydra-server-includes";
      inputs.nix.follows = "nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    hydra,
    nixpkgs,
    nixpkgs-unstable,
    utils,
    deploy,
    ragenix,
    nix,
    fenix,
    tullia,
    ...
  } @ inputs:
    inputs.std.growOn {
      inherit inputs;
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
      overlays = [
        fenix.overlay
        nix.overlay
        hydra.overlay
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

      defaultSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      mkChecks = systems: pkgs:
        utils.lib.eachSystem systems (system: {
          checks = builtins.foldl' (acc: pkg: acc // {${pkg} = (pkgsForSystem system).${pkg};}) {} pkgs;
        });
    in
      utils.lib.eachSystem defaultSystems
      (system: let
        legacyPackages = pkgsForSystem system;
        unstablePackages = unstablePkgsForSystem system;
      in
        rec {
          inherit legacyPackages;

          packages = {inherit (self.${system}.cli.packages) bitte;};
          defaultPackage = packages.bitte;
        }
        // tullia.fromSimple system {
          tasks = import tullia/tasks.nix self;
          actions = import tullia/actions.nix;
        })
      // {
        inherit lib;
        # eta reduce not possibe since flake check validates for "final" / "prev"
        overlay = nixpkgs.lib.composeManyExtensions overlays;
        profiles = lib.mkModules ./profiles;
        nixosModules = lib.mkModules ./modules;
        nixosModule.imports = builtins.attrValues self.nixosModules;
        devshellModule = import ./devshellModule.nix;
      }
      // mkChecks defaultSystems [
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
        "hydra"
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
        "vault-backend"
      ]
      // mkChecks ["x86_64-linux"] [
        "agenix"
        "glusterfs"
        "nomad-follower"
        "vault-bin"
        "victoriametrics"
      ]);
}
