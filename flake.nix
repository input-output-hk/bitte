{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/43cdc5b364511eabdcad9fde639777ffd9e5bab1"; # nixos-21.05
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nix.url = "github:kreisys/nix/goodnix-maybe-dont-functor";
    cli.url = "github:input-output-hk/bitte-cli";
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

  outputs =
    { self, hydra, nixpkgs, utils, cli, deploy, ragenix, nix, ... }@inputs:
    let

      overlays = [
        nix.overlay
        (_: prev: { inherit (cli.packages."${prev.system}") bitte; })
        hydra.overlay
        deploy.overlay
        localPkgsOverlay
        terraformProvidersOverlay
      ];
      terraformProvidersOverlay =
        import ./terraform-providers-overlay.nix inputs;
      localPkgsOverlay = import ./overlay.nix inputs;

      pkgsForSystem = system:
        import nixpkgs {
          inherit overlays system;
          config.allowUnfree = true; # for ssm-session-manager-plugin
        };

      lib = import ./lib {
        inherit (nixpkgs) lib;
        inherit inputs;
      };

    in utils.lib.eachSystem [ "x86_64-linux" ] (system: rec {

      legacyPackages = pkgsForSystem system;

      inherit (legacyPackages) devShell;

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
    };
}
