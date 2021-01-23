{
  description = "zfs image for amazon";
  outputs = { self, ... }:
  {
    nixosModules = {
      make-zfs-image = ./make-zfs-image.nix;
      zfs-runtime = ./zfs-runtime.nix;
    };
  };
}
