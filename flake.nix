{
  description = "Flake containing Bitte clusters";

  inputs = {
    utils.url = "github:kreisys/flake-utils";
    cli.url = "github:input-output-hk/bitte-cli";
    nix.url = "github:NixOS/nix/4e9cec79bf5302108a031b3910f63baccf719eb5";

    ops-lib.url = "github:input-output-hk/ops-lib";
    ops-lib.flake = false;

    # TODO use upstream/nixpkgs
    terranix = {
      url = "github:manveru/terranix/cleanup";
      flake = false;
    };
  };

  outputs = { self, ops-lib, nix, nixpkgs, terranix, utils, cli, ... }:
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
      nixosConfigurations = {
        # attrs of interest:
        # * config.system.build.zfsImage
        # * config.system.build.uploadAmi
        zfs-ami = import "${nixpkgs}/nixos" {
          configuration = { pkgs, lib, ... }: {
            imports = [
              ./amis/make-zfs-image.nix
              ./amis/zfs-runtime.nix
              "${nixpkgs}/nixos/modules/profiles/headless.nix"
              "${nixpkgs}/nixos/modules/virtualisation/ec2-data.nix"
            ];
            nix.package = pkgs.nixFlakes;
            nix.extraOptions = ''
              experimental-features = nix-command flakes
            '';
            systemd.services.amazon-shell-init.path = with pkgs; [ git sops ];
            nixpkgs = {
              config.allowUnfreePredicate = x:
              builtins.elem (lib.getName x) [ "ec2-ami-tools" "ec2-api-tools" ];

              inherit (self) overlays;
            };

            zfs.regions = [
              "ca-central-1"
              "ap-northeast-1"
              "ap-northeast-2"
              "eu-central-1"
              "eu-west-1"
              "us-east-1"
              "us-east-2"
            ];
          };
          system = "x86_64-linux";
        };
      };
    };
}
