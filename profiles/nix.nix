{ pkgs, config, ... }: {
  nix = {
    package = pkgs.nixFlakes;
    gc.automatic = true;
    gc.options = "--max-freed $((10 * 1024 * 1024))";
    optimise.automatic = true;
    autoOptimiseStore = true;
    extraOptions = ''
      tarball-ttl = ${toString (60 * 60 * 72)}
      show-trace = true
      experimental-features = nix-command flakes ca-references recursive-nix
    '';
    systemFeatures = [ "recursive-nix" "nixos-test" ];

    binaryCaches = [
      "https://hydra.iohk.io"
      config.cluster.s3Cache
    ];

    binaryCachePublicKeys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      config.cluster.s3CachePubKey
    ];
  };
}
