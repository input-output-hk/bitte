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

    settings = {
      auto-optimise-store = true;
      system-features = ["recursive-nix" "nixos-test"];
      tarball-ttl = 60 * 60 * 72;
      show-trace = true;
      experimental-features = "nix-command flakes recursive-nix";
      builders-use-substitutes = true;

      substituters =
        [
          "https://cache.iog.io"
        ]
        ++ lib.optional (builtins.elem deployType ["aws" "awsExt"]) "${config.cluster.s3Cache}";

      trusted-public-keys =
        [
          "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
        ]
        ++ lib.optional (builtins.elem deployType ["aws" "awsExt"]) "${config.cluster.s3CachePubKey}";
    };

    registry.nixpkgs = {
      flake = self.inputs.nixpkgs;
      from = {
        id = "nixpkgs";
        type = "indirect";
      };
    };
  };
}
