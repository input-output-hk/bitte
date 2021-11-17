{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-21.05";
    nixpkgs-terraform.url =
      "github:input-output-hk/nixpkgs/iohk-terraform-2021-06";
    utils.url = "github:numtide/flake-utils";
    bitte-cli.url = "github:input-output-hk/bitte-cli/30d7d141cb349246e8aa1254d848b51f6940a2a1";
    bitte-cli.inputs.utils.follows = "utils";
    hydra.url = "github:kreisys/hydra/hydra-server-includes";
    hydra.inputs.nix.follows = "nix";
    hydra.inputs.nixpkgs.follows = "nixpkgs";
    terranix.url = "github:terranix/terranix";
    terranix.inputs.nixpkgs.follows = "nixpkgs";
    deploy.url = "github:input-output-hk/deploy-rs";
    deploy.inputs.fenix.follows = "bitte-cli/fenix";
    deploy.inputs.nixpkgs.follows = "bitte-cli/nixpkgs";
    deploy.inputs.utils.follows = "utils";
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

    nix.url = "github:NixOS/nix/c6fa7775de413a799b9a137dceced5dcf0f5e6ed";
    nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self
    , hydra
    , nixpkgs
    , utils
    , bitte-cli
    , deploy
    , ...
    }@inputs:
    let

      overlays = [
        bitte-cli.overlay
        # `bitte` build depend on nixpkgs-unstable rust version
        # TODO: remove when bitte itself is bumped
        (final: prev: { inherit (bitte-cli.legacyPackages.${final.system}) bitte; })
        hydra.overlay
        deploy.overlay
        localPkgsOverlay
      ];
      localPkgsOverlay = import ./overlay.nix inputs;

      pkgsForSystem = system: import nixpkgs {
        inherit overlays system;
        config.allowUnfree = true; # for ssm-session-manager-plugin
      };

      lib = import ./lib { inherit (nixpkgs) lib; inherit inputs; };

    in
    utils.lib.eachSystem [ "x86_64-linux" ]
      (system: rec {

        legacyPackages = pkgsForSystem system;

        devShell = legacyPackages.devShell;

        hydraJobs =
          let
            constituents = {
              inherit (legacyPackages)
                asgAMIClients
                asgAMICores
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
                ssm-agent
                terraform-with-plugins
                vault-backend
                vault-bin
                ;
            };
          in
          {
            inherit constituents;
            required = legacyPackages.mkRequired constituents;
          };

      }) // {
      inherit lib;
      overlay = nixpkgs.lib.composeManyExtensions overlays;
      profiles = lib.mkModules ./profiles;
      nixosModules = lib.mkModules ./modules;
      nixosModule.imports = builtins.attrValues self.nixosModules;
    };
}
