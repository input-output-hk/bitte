{
  description = "Flake containing Bitte clusters";

  inputs = {
    utils.url = "github:kreisys/flake-utils";
    cli.url = "github:input-output-hk/bitte-cli";
    nix.url = "github:NixOS/nix/4e9cec79bf5302108a031b3910f63baccf719eb5";

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

  outputs = { self, nix, nixpkgs, terranix, utils, cli, ... }:
  (utils.lib.simpleFlake {
      inherit nixpkgs;
      name = "bitte";
      systems = [ "x86_64-darwin" "x86_64-linux" ];

      overlays = [
        cli
        ./overlay.nix
        (final: prev: {
          inherit (nix.packages.${final.system}) nix;
          nixFlakes = final.nix;
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

    }) // {
      lib = import ./lib { inherit nixpkgs; };
      nixosModules = self.lib.importNixosModules ./modules;
    };
}
