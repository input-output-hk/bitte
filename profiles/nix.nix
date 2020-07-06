{ pkgs, ... }: {
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

    binaryCaches = [ "https://hydra.iohk.io" "https://manveru.cachix.org" ];

    binaryCachePublicKeys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "manveru.cachix.org-1:L5nJHSinfA2K5dDCG3KAEadwf/e3qqhuBr7yCwSksXo="
    ];
  };
}
