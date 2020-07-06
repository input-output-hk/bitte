{ pkgs }:
with pkgs;
mkShellNoCC {
  # TF_LOG = "TRACE";
  buildInputs = [
    awscli
    bitte
    consul
    consul-template
    crystal
    crystal2nix
    nixFlakes
    nixos-rebuild
    nomad
    python38Packages.pyhcl
    sops
    terraform-with-plugins
    cfssl
    ssm-session-manager-plugin
    vault-bin
    cachix

    # nodejs-slim-10_x
    # mill
    # jre
    # scala_2_12
    # dbeaver
    # asciinema
  ];
}
