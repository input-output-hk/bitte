{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-crystal.url = "github:manveru/nixpkgs/crystal-0.35";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    inclusive.url = "github:manveru/nix-inclusive";
    utils.url = "github:numtide/flake-utils";
    bitte-cli.url = "github:input-output-hk/bitte-cli";
    # bitte-cli.url = "/home/manveru/github/input-output-hk/bitte-cli";
    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
    terranix = {
      url = "github:manveru/terranix/cleanup";
      flake = false;
    };
    netboot = {
      url = "github:grahamc/netboot.nix";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, utils, ... }:
    (utils.lib.eachDefaultSystem (system: rec {
      overlay = import ./overlay.nix { inherit system self; };

      legacyPackages = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # for ssm-session-manager-plugin
        overlays = [ overlay ];
      };

      inherit (legacyPackages) devShell;

      packages = {
        inherit (legacyPackages)
          bitte nixos-rebuild nixFlakes sops crystal terraform-with-plugins
          sops-add ssm-agent cfssl consul;
      };

      apps.bitte = utils.lib.mkApp { drv = legacyPackages.bitte; };
    })) // (let
      pkgs = import nixpkgs {
        overlays = [ self.overlay.x86_64-linux ];
        system = "x86_64-linux";
      };
    in { inherit (pkgs) nixosModules nixosConfigurations clusters; });
}
