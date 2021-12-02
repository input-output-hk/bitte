{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs-core.url = "github:nixos/nixpkgs/release-21.05";
    nixpkgs-client.url = "github:nixos/nixpkgs/release-21.05";
    nixpkgs-auxiliary.url = "github:nixos/nixpkgs/nixos-21.11";
    nixpkgs-unstable.url =
      "github:nixos/nixpkgs/7733d9cae98ab91f36d35005d8aef52873d23b5b";

    nixpkgs.follows = "nixpkgs-core";
    nix.url = "github:NixOS/nix/c6fa7775de413a799b9a137dceced5dcf0f5e6ed";
    nix.inputs.nixpkgs.follows = "nixpkgs-core";

    fenix.url = "github:nix-community/fenix";

    cli.url = "github:input-output-hk/bitte-cli";
    cli.inputs.fenix.follows = "fenix";
    cli.inputs.nixpkgs.follows = "nixpkgs-auxiliary";

    deploy.url = "github:input-output-hk/deploy-rs";
    deploy.inputs.fenix.follows = "fenix";
    deploy.inputs.nixpkgs.follows = "nixpkgs-auxiliary";

    terranix.url = "github:terranix/terranix";
    terranix.inputs.nixpkgs.follows = "blank";

    utils.url = "github:numtide/flake-utils";
    blank.url = "github:divnix/blank";

    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
    nomad-source = {
      url = "github:input-output-hk/nomad/release-1.1.6";
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
    { self, hydra, nixpkgs, nixpkgs-unstable, utils, cli, deploy, ... }@inputs:
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

    in
    utils.lib.eachSystem [ "x86_64-linux" ]
      (system: rec {

        legacyPackages = pkgsForSystem system;

        inherit (legacyPackages) devShell;

        hydraJobs =
          let
            constituents = {
              inherit (legacyPackages)
                asgAMIClients asgAMICores bitte cfssl ci-env consul cue glusterfs
                grafana-loki haproxy haproxy-auth-request haproxy-cors nixFlakes
                nomad nomad-autoscaler oauth2-proxy sops ssm-agent
                terraform-with-plugins vault-backend vault-bin;
            };
          in
          {
            inherit constituents;
            required = legacyPackages.mkRequired constituents;
          };

      }) // {
      inherit lib;
      # eta reduce not possibe since flake check validates for "final" / "prev"
      overlay = final: prev: nixpkgs.lib.composeManyExtensions overlays final prev;
      profiles = lib.mkModules ./profiles;
      nixosModules = lib.mkModules ./modules;
      nixosModule.imports = builtins.attrValues self.nixosModules;
    };
}
