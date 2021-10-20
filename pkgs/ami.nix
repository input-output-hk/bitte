{ nixpkgs, system, extraModules ? [ ] }:
let
  modules = [
    ({ pkgs, modulesPath, ... }: {
      nix.package = pkgs.nixUnstable;
      nix.binaryCaches = [ "https://hydra.iohk.io" ];
      nix.binaryCachePublicKeys =
        [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];

      nix.registry.nixpkgs.flake = nixpkgs;

      nix.nixPath =
        [ "nixpkgs=${pkgs.path}" "nixos-config=/etc/nixos/configuration.nix" ];

      nix.extraOptions = ''
        experimental-features = nix-command flakes ca-references
      '';

      environment.systemPackages = [ pkgs.git ];
    })
  ] ++ extraModules;
in nixpkgs.lib.nixosSystem { inherit system modules; }
