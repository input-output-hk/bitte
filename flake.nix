{
  description = "Flake containing Bitte clusters";

  inputs = {
    utils.url = "github:kreisys/flake-utils";
    cli.url = "github:input-output-hk/bitte-cli/decalisssystemd";

    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
    # TODO use upstream/nixpkgs
    terranix = {
      url = "github:manveru/terranix/cleanup";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, terranix, utils, cli, ... }:
    utils.lib.simpleFlake {
      inherit nixpkgs;
      name = "bitte";
      systems = [ "x86_64-darwin" "x86_64-linux" ];

      overlays = [
        cli.overlay
        ./overlay.nix
        (final: prev: {
          lib = nixpkgs.lib.extend (final: prev: {
            terranix = import (terranix + "/core");
          });
        })
      ];

      packages = { devShell, bitte }: {
        inherit devShell bitte;
        defaultPackage = bitte;
      };

      hydraJobs = { devShell, bitte }: {
        inherit bitte;
        devShell = devShell.overrideAttrs (_: {
          nobuildPhase = "touch $out";
        });
      };

      config.allowUnfreePredicate = pkg:
      let name = nixpkgs.lib.getName pkg;
      in
      (builtins.elem name [ "ssm-session-manager-plugin" ])
      || throw "unfree not allowed: ${name}";

      lib = {
        mkClusters = import ./lib/clusters.nix;

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

      } // (
      let
        pkgs = import nixpkgs {
          overlays = [ self.overlay ];
          localSystem = "x86_64-darwin";
          crossSystem = "x86_64-linux";
        };
      in {

        nixosConfigurations = self.lib.mkNixosConfigurations self.clusters;

        nixosModules = self.lib.importNixosModules ./modules;

        clusters = self.lib.mkClusters {
          root = ./clusters;
          inherit (pkgs) lib;
          inherit self pkgs;
        };
      }
    );
}
