{ system, self }:
final: prev: {
  # Bitte itself
  bitte = let
    bitte-nixpkgs = import self.inputs.nixpkgs {
      inherit system;
      overlays = [
        (final: prev: {
          vault-bin = self.inputs.bitte.legacyPackages.${system}.vault-bin;
        })
        self.inputs.bitte-cli.overlay.${system}
      ];
    };
  in bitte-nixpkgs.bitte;

  # Tools needed for development
  devShell = prev.mkShell {
    LOG_LEVEL = "debug";

    buildInputs = [
      final.bitte
      final.terraform-with-plugins
      prev.sops
      final.vault-bin
      final.glibc
      final.gawk
      final.openssl
      final.cfssl
    ];
  };

  inherit (self.inputs.bitte.legacyPackages.${system})
    vault-bin terraform-with-plugins;

  nixosConfigurations =
    self.inputs.bitte.legacyPackages.${system}.mkNixosConfigurations
    final.clusters;
  
  clusters = self.inputs.bitte.legacyPackages.${system}.mkClusters {
    root = ./clusters;
    inherit self system;
  };
}
