{ ... }: {
  nix = {
    binaryCaches = [ "https://hydra.iohk.io" ];

    binaryCachePublicKeys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
  };
}
