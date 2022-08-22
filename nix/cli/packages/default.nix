{
  inputs,
  cell,
}: let
  pkgs = import inputs.nixpkgs-unstable {
    inherit (inputs.nixpkgs) system;
    overlays = [inputs.fenix.overlay];
  };
in {
  bitte = pkgs.callPackage ./cli {toolchain = "stable";};
}
