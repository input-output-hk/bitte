{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-21.05";
    nixpkgs-client.url = "github:nixos/nixpkgs/release-21.05";
    nixpkgs-auxiliary.url = "github:nixos/nixpkgs/nixos-21.11";

    # currently includes `computeLocks` fix - so follows are not screwed
    nix-auxiliary.url =
      "github:NixOS/nix/d1aaa7ef71713b6693ad3ddf8704ce62bab82095";
    nix-auxiliary.inputs.nixpkgs.follows = "nixpkgs-auxiliary";

    # Legacy alias / TODO
    nix.url = "github:NixOS/nix/2.6.0";

    fenix.url = "github:nix-community/fenix";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    cli.url = "github:input-output-hk/bitte-cli";
    cli.inputs.fenix.follows = "fenix";
    cli.inputs.nixpkgs.follows = "nixpkgs-auxiliary";
    cli.inputs.nix.follows = "nix-auxiliary";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs-auxiliary";
    agenix-cli.url = "github:cole-h/agenix-cli";
    agenix-cli.inputs.nixpkgs.follows = "nixpkgs-auxiliary";

    ragenix.url = "github:yaxitech/ragenix";
    ragenix.inputs.nixpkgs.follows = "nixpkgs-auxiliary";

    deploy.url = "github:input-output-hk/deploy-rs";
    deploy.inputs.fenix.follows = "fenix";
    deploy.inputs.nixpkgs.follows = "nixpkgs-auxiliary";

    terranix.url = "github:terranix/terranix";
    terranix.inputs.nixpkgs.follows = "blank";

    utils.url = "github:numtide/flake-utils";
    blank.url = "github:divnix/blank";

    nomad.url = "github:input-output-hk/nomad/release-1.2.2";
    nomad.inputs.nixpkgs.follows = "nixpkgs";
    nomad.inputs.nix.follows = "nix";

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

  outputs = { self, hydra, nixpkgs, utils, cli, deploy, ragenix, ... }@inputs:
    let

      overlays = [
        cli.overlay
        # `bitte` build depend on nixpkgs-unstable rust version
        # TODO: remove when bitte itself is bumped
        (final: prev: { inherit (cli.legacyPackages."${final.system}") bitte; })
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
