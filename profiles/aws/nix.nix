{ config, ... }: {
  imports = [ ../nix.nix ];

  nix = {
    binaryCaches = [ config.cluster.s3Cache ];
    binaryCachePublicKeys = [ config.cluster.s3CachePubKey ];
  };
}
