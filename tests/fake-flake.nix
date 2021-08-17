{
  description = "Test";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
  outputs = { self, nixpkgs, ... }@inputs:
    let pkgs = import nixpkgs { system = "x86_64-linux"; };
    in { legacyPackages.x86_64-linux = pkgs; };
}
