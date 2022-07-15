{pkgs, ...}: {
  # We are using the overlay from hydra master which exposes the pkg as `hydra`
  # but we are using the module from nixpkgs which defaults this to `pkgs.hydra-unstable`
  # however now `pkgs.hydra` is unstabler than `pkgs.hydra-unstable` and that's what we want
  # because we h4rdc0r3 l33t h4xx00r
  services.hydra.package = pkgs.hydra;
}
