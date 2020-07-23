{ pkgs }:
with pkgs;
mkShellNoCC {
  # TF_LOG = "TRACE";

  AWS_DEFAULT_REGION = "eu-central-1";
  BITTE_CLUSTER = "midnight-testnet";
  AWS_PROFILE = "midnight";
  LOG_LEVEL = "debug";
  VAULT_ADDR = "https://vault.bitte.project42.iohkdev.io";
  NOMAD_ADDR = "https://nomad.bitte.project42.iohkdev.io";
  CONSUL_HTTP_ADDR = "https://consul.bitte.project42.iohkdev.io";

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
    nixfmt
    dnsutils

    # nodejs-slim-10_x
    # mill
    # jre
    # scala_2_12
    # dbeaver
    # asciinema
  ];
}
