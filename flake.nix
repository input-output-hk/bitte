{
  description = "Flake containing Bitte clusters";

  inputs = {
    crystal.follows = "bitte-cli/crystal";
    nixpkgs.follows = "bitte-cli/nixpkgs";
    nixpkgs-terraform.url = "github:manveru/nixpkgs/terraform-providers";
    inclusive.url = "github:input-output-hk/nix-inclusive";
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
  };

  outputs = { self, crystal, nixpkgs, utils, bitte-cli, ... }:
    (utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (system: rec {
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
          ssm-agent cfssl consul;
      };

      hydraJobs = packages;

      apps.bitte = utils.lib.mkApp { drv = legacyPackages.bitte; };
    })) // (let
      pkgs = import nixpkgs {
        overlays = [ self.overlay.x86_64-linux ];
        system = "x86_64-linux";
      };
    in { inherit (pkgs) nixosModules clusters nomadJobs; });
}
