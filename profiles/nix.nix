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

    binaryCaches = [
      "https://hydra.iohk.io"
      "https://manveru.cachix.org"
      "s3://iohk-midnight-bitte/infra/binary-cache/?region=eu-central-1"
    ];

    binaryCachePublicKeys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "manveru.cachix.org-1:L5nJHSinfA2K5dDCG3KAEadwf/e3qqhuBr7yCwSksXo="
      "iohk-midnight-bitte-0:CM87AnQ46Y1fbPC9NT7LfxEd7eDqfg51b9Ly2jlG+CA="
    ];
  };
}
