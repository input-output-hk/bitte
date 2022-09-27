{
  pkgs,
  lib,
  config,
  self,
  ...
}: let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
in {
  nix = {
    gc.automatic = true;
    gc.options = "--max-freed $((10 * 1024 * 1024))";
    optimise.automatic = true;
    autoOptimiseStore = true;
    extraOptions = ''
      tarball-ttl = ${toString (60 * 60 * 72)}
      show-trace = true
      experimental-features = nix-command flakes recursive-nix
      builders-use-substitutes = true
    '';
    registry.nixpkgs = {
      flake = self.inputs.nixpkgs;
      from = {
        id = "nixpkgs";
        type = "indirect";
      };
    };
    systemFeatures = ["recursive-nix" "nixos-test"];

    binaryCaches =
      [
        "https://cache.iog.io"
      ]
      ++ lib.optional (deployType == "aws") "${config.cluster.s3Cache}";

    binaryCachePublicKeys =
      [
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      ]
      ++ lib.optional (deployType == "aws") "${config.cluster.s3CachePubKey}";
  };
}
