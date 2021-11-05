{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
    nixpkgs-terraform.url =
      "github:input-output-hk/nixpkgs/iohk-terraform-2021-06";
    utils.url = "github:kreisys/flake-utils";
    bitte-cli.url = "github:input-output-hk/bitte-cli";
    hydra.url = "github:kreisys/hydra/hydra-server-includes";
    hydra.inputs.nix.follows = "nix";
    hydra.inputs.nixpkgs.follows = "nixpkgs";
    hydra-provisioner.url = "github:input-output-hk/hydra-provisioner";
    hydra-provisioner.inputs.nixpkgs.follows = "nixpkgs";
    hydra-provisioner.inputs.utils.follows = "utils";
    deploy.url = "github:input-output-hk/deploy-rs";
    deploy.inputs.nixpkgs.follows = "bitte-cli/nixpkgs";
    deploy.inputs.naersk.follows = "bitte-cli/naersk";
    deploy.inputs.utils.follows = "bitte-cli/utils";
    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
    terranix = {
      url = "github:manveru/terranix/cleanup";
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
    { self, hydra, hydra-provisioner, nixpkgs, utils, bitte-cli, ... }@inputs:
    let
      lib = import ./lib {
        inherit (nixpkgs) lib;
        inherit inputs;
      } // {
        inherit (utils.lib) simpleFlake;
      };
    in lib.simpleFlake rec {
      inherit lib nixpkgs;

      systems = [ "x86_64-linux" ];

      preOverlays = [ bitte-cli hydra-provisioner hydra ];
      overlay = import ./overlay.nix inputs;
      config.allowUnfree = true; # for ssm-session-manager-plugin

      shell = { devShell }: devShell;

      packages = { bitte, cfssl, consul, cue, glusterfs, grafana-loki, haproxy
        , haproxy-auth-request, haproxy-cors, nixFlakes, nomad, nomad-autoscaler
        , oauth2-proxy, sops, ssm-agent, terraform-with-plugins, vault-backend
        , vault-bin, ci-env }@pkgs:
        pkgs;

      hydraJobs = { bitte, cfssl, consul, cue, glusterfs, grafana-loki, haproxy
        , haproxy-auth-request, haproxy-cors, nixFlakes, nomad, nomad-autoscaler
        , oauth2-proxy, sops, ssm-agent, terraform-with-plugins, vault-backend
        , vault-bin, ci-env, mkRequired, asgAMI }@pkgs:
        let constituents = builtins.removeAttrs pkgs [ "mkRequired" ];
        in constituents // { required = mkRequired constituents; };

      apps = { bitte }: {
        bitte = utils.lib.mkApp { drv = bitte; };
        defaultApp = utils.lib.mkApp { drv = bitte; };
      };

      nixosModules = (lib.mkModules ./modules) // {
        hydra-provisioner = hydra-provisioner.nixosModule;
      };

      # Nix supports both singular `nixosModule` and plural `nixosModules`
      # so I use the singular as a `defaultNixosModule` that won't spew a warning.
      nixosModule.imports = builtins.attrValues self.nixosModules;

      # Outputs that aren't directly supported by simpleFlake can go here
      # instead of having to doubleslash.
      extraOutputs = { profiles = lib.mkModules ./profiles; };
    };
}
