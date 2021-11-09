{ nixpkgs, system, extraModules ? [ ] }:
let
  modules = [
    ({ pkgs, modulesPath, ... }: {
      imports =
        [
          "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix"
          (import ./shared-config.nix nixpkgs)
        ];
    })
  ] ++ extraModules;
in nixpkgs.lib.nixosSystem { inherit system modules; }
