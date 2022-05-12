{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

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
    hydra.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, hydra, nixpkgs, nixpkgs-unstable, utils, deploy, ragenix, fenix, ... }@inputs:
    let

      overlays = [
        fenix.overlay
        hydra.overlay
        deploy.overlay
        localPkgsOverlay
        terraformProvidersOverlay
        (_: prev: { inherit (self.packages."${prev.system}") bitte; })
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

    in utils.lib.eachSystem [
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
      devShells.default = legacyPackages.devShell;
      devShells.cli = with unstablePackages;
        mkShell {
          RUST_BACKTRACE = "1";
          RUST_SRC_PATH = "${rustPkg}/lib/rustlib/src/rust/library";

          buildInputs = [
            legacyPackages.treefmt
            shfmt
            nodePackages.prettier
            cfssl
            sops
            openssl
            zlib
            pkg-config
            rustPkg
            rust-analyzer-nightly
          ] ++ lib.optionals stdenv.isDarwin (with darwin;
            with apple_sdk.frameworks; [
              libiconv
              libresolv
              Libsystem
              SystemConfiguration
              Security
              CoreFoundation
            ]);
        };


      packages.bitte =  unstablePackages.callPackage ./cli/package.nix { inherit toolchain; };
      defaultPackage = packages.bitte;

      hydraJobs = let
        constituents = {
          inherit (legacyPackages)
            bitte cfssl ci-env consul cue glusterfs grafana-loki haproxy
            haproxy-auth-request haproxy-cors nixFlakes nomad nomad-autoscaler
            oauth2-proxy sops terraform-with-plugins vault-backend vault-bin;
        };
      in {
        inherit constituents;
        required = legacyPackages.mkRequired constituents;
      };

    }) // {
      inherit lib;
      # eta reduce not possibe since flake check validates for "final" / "prev"
      overlay = nixpkgs.lib.composeManyExtensions overlays;
      profiles = lib.mkModules ./profiles;
      nixosModules = (lib.mkModules ./modules) // {
        # Until ready to update to the new age module options
        # agenix = ragenix.nixosModules.age;
      };
      nixosModule.imports = builtins.attrValues self.nixosModules;
      devshellModule = import ./devshellModule.nix;
    };
}
