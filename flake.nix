{
  description = "Flake containing Bitte clusters";

  inputs = {
    crystal.follows = "bitte-cli/crystal";
    nixpkgs.follows = "bitte-cli/nixpkgs";
    nixpkgs-terraform.url = "github:manveru/nixpkgs/terraform-providers";
    inclusive.url = "github:input-output-hk/nix-inclusive";
    utils.url = "github:numtide/flake-utils";
    # bitte-cli.url = "github:input-output-hk/bitte-cli/decalisssystemd";
    bitte-cli.url = "/Users/kreisys/Werk/iohk/bitte-cli";
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

  outputs = { self, inclusive, crystal, nixpkgs, utils, bitte-cli, ... }:
    let
      name = "bitte-ops";
      systems = [ "x86_64-darwin" "x86_64-linux" ];
      overlay = nixpkgs.lib.composeExtensions
        (import ./overlay.nix { inherit self; })
          (final: prev: {
            lib = prev.lib.extend (final: prev: {
              inherit (nixpkgs.lib) nixosSystem;
              inherit (inclusive.lib) inclusive;
            });

            ${name} = {
              inherit (final)
              nixos-rebuild nixFlakes sops crystal terraform-with-plugins
              ssm-agent cfssl consul consul-template devShell;
            };
          });

      simpleFlake = utils.lib.simpleFlake {
        inherit name systems overlay self nixpkgs;
        preOverlays = [
          bitte-cli.overlay
          crystal.overlay
        ];
        config.allowUnfreePredicate = pkg:
          let name = nixpkgs.lib.getName pkg;
          in
          (builtins.elem name [ "ssm-session-manager-plugin" ])
          || throw "unfree not allowed: ${name}";
      };
      old =
        (utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" ] (system: rec {
          overlay = nixpkgs.lib.composeExtensions
            (final: prev: { inherit (nixpkgs) lib; })
            (import ./overlay.nix { inherit self; });

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
        })) // (
          let
            pkgs = import nixpkgs {
              overlays = [ self.overlay.x86_64-linux ];
              system = "x86_64-linux";
            };
          in
          { inherit (pkgs) nixosModules nixosConfigurations clusters nomadJobs; }
        );
    in
    simpleFlake // (
      let
        pkgs = import nixpkgs {
          overlays = [ overlay ];
          system = "x86_64-linux";
        };
      in {
        lib = let
        in {
          mkClusters = args:
          import ./lib/clusters.nix ({
            inherit pkgs;
            inherit (pkgs) lib;
          } // args);

          mkNixosConfigurations = clusters: let
            inherit (nixpkgs.lib) pipe mapAttrsToList nameValuePair flatten listToAttrs;
          in
          pipe clusters [
            (mapAttrsToList (clusterName: cluster:
            mapAttrsToList
            (name: value: nameValuePair "${clusterName}-${name}" value)
            (cluster.nodes // cluster.groups)))
            flatten
            listToAttrs
          ];

          importNixosModules = dir: let
            inherit dir;

            inherit (nixpkgs.lib)
            hasSuffix nameValuePair filterAttrs readDir mapAttrs' removeSuffix;

            mapFilterAttrs = sieve: f: attrs: filterAttrs sieve (mapAttrs' f attrs);
            paths = builtins.readDir dir;
          in mapFilterAttrs (key: value: value != null) (name: type:
          nameValuePair (removeSuffix ".nix" name)
          (if name != "default.nix" && type == "regular" && hasSuffix ".nix" name then
          (import (dir + "/${name}"))
          else
          null)) paths;
        };

        nixosConfigurations = self.lib.mkNixosConfigurations self.clusters;

        nixosModules = self.lib.importNixosModules ./modules;

        inherit (pkgs) nomadJobs;
        clusters = self.lib.mkClusters {
          root = ./clusters;
          inherit (pkgs) system;
          inherit self;
        };
      }
    );
}
