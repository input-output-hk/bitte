{ lib, removeReferencesTo, crystal }:
crystal.buildCrystalPackage {
  pname = "systemd-runner";
  version = "0.0.1";
  format = "crystal";

  src = ./.;

  nativeBuildInputs = [ removeReferencesTo ];

  # We only need a tiny closure for this.
  postInstall = ''
    remove-references-to -t ${crystal.lib} $out/bin/*
  '';

  crystalBinaries.systemd-runner = {
    src = "systemd_runner.cr";
    options = [ "--verbose" "--release" ];
  };
}
