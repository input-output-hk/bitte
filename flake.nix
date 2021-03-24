{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url =
      "github:NixOS/nixpkgs?rev=b8c367a7bd05e3a514c2b057c09223c74804a21b";
    # nixpkgs-terraform.url = "github:anandsuresh/nixpkgs/backport";
    nixpkgs-terraform.url = "github:manveru/nixpkgs/iohk-terraform";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    inclusive.url = "github:input-output-hk/nix-inclusive";
    utils.url = "github:numtide/flake-utils";
    bitte-cli.url = "github:input-output-hk/bitte-cli";
    nix.url = "github:NixOS/nix?rev=b19aec7eeb8353be6c59b2967a511a5072612d99";
    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
    terranix = {
      url = "github:manveru/terranix/cleanup";
      flake = false;
    };
    nomad-source = {
      url = "github:manveru/nomad/release-1.0.4";
      flake = false;
    };
    levant-source = {
      url =
        "github:hashicorp/levant?rev=05c6c36fdf24237af32a191d2b14756dbb2a4f24";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, utils, bitte-cli, ... }@inputs:
    (utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (system: rec {
      overlay = import ./overlay.nix inputs;

      legacyPackages = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # for ssm-session-manager-plugin
        overlays = [ overlay ];
      };

      inherit (legacyPackages) devShell nixosModules;

      packages = {
        inherit (legacyPackages)
          bitte nixos-rebuild nixFlakes sops terraform-with-plugins ssm-agent
          cfssl consul;
      };

      hydraJobs = packages;

      apps.bitte = utils.lib.mkApp { drv = legacyPackages.bitte; };

    })) // {
      mkHashiStack = import ./lib/mk-hashi-stack.nix;
    };
}
