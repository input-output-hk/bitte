{
  description = "Flake containing Bitte clusters";
  inputs.std.url = "github:divnix/std";
  # 21.05 doesn't yet fullfill all contracts that std consumes
  # inputs.std.inputs.nixpkgs.follows = "nixpkgs";
  inputs.n2c.url = "github:nlewo/nix2container";
  inputs.data-merge.url = "github:divnix/data-merge";
  inputs.capsules.url = "github:input-output-hk/devshell-capsules";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.11";
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

    nomad.url = "github:input-output-hk/nomad/release-1.2.6";
    nomad-driver-nix.url = "github:input-output-hk/nomad-driver-nix";
    nomad-follower.url = "github:input-output-hk/nomad-follower";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
    vulnix = {
      url = "github:dermetfan/vulnix/runtime-deps";
      flake = false;
    };

    # DEPRECATED: will be replaces by cicero soon
    hydra.url = "github:kreisys/hydra/hydra-server-includes";
    hydra.inputs.nix.follows = "nix";
    hydra.inputs.nixpkgs.follows = "nixpkgs";
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
    ...
  } @ inputs:
    inputs.std.growOn {
      inherit inputs;
      cellsFrom = ./nix;
      organelles = [
        (inputs.std.devshells "devshells")

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

      toolchain = "stable";
    in
      utils.lib.eachSystem [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ] (system: let
        legacyPackages = pkgsForSystem system;
        unstablePackages = unstablePkgsForSystem system;
        rustPkg = unstablePackages.fenix."${toolchain}".withComponents [
          "cargo"
          "clippy"
          "rust-src"
          "rustc"
          "rustfmt"
        ];
      in rec {
        inherit legacyPackages;

        packages.bitte = unstablePackages.callPackage ./cli/package.nix {inherit toolchain;};
        defaultPackage = packages.bitte;

        hydraJobs = let
          constituents = {
            inherit
              (legacyPackages)
              bitte
              cfssl
              ci-env
              consul
              cue
              glusterfs
              grafana-loki
              haproxy
              haproxy-auth-request
              haproxy-cors
              nixFlakes
              nomad
              nomad-autoscaler
              oauth2-proxy
              sops
              terraform-with-plugins
              vault-backend
              vault-bin
              ;
          };
        in {
          inherit constituents;
          required = legacyPackages.mkRequired constituents;
        };
      })
      // {
        inherit lib;
        # eta reduce not possibe since flake check validates for "final" / "prev"
        overlay = nixpkgs.lib.composeManyExtensions overlays;
        profiles = lib.mkModules ./profiles;
        nixosModules =
          (lib.mkModules ./modules)
          // {
            # Until ready to update to the new age module options
            # agenix = ragenix.nixosModules.age;
          };
        nixosModule.imports = builtins.attrValues self.nixosModules;
        devshellModule = import ./devshellModule.nix;
      });
}
