{ bitte, pkgs, writeText, system, mkShell }:

mkShell {
  # for bitte-cli
  LOG_LEVEL = "debug";

  NIX_USER_CONF_FILES = writeText "nix.conf" ''
    experimental-features = nix-command flakes ca-references
    substituters = https://cache.nixos.org
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
  '';

  buildInputs = with pkgs; [
    bitte
    nixos-rebuild
    terraform-with-plugins
    scaler-guard
    sops
    vault
    openssl
    cfssl
    nixfmt
    awscli
    nomad
    consul
    consul-template
    python38Packages.pyhcl
    direnv
    nixFlakes
    jq
  ];
}
