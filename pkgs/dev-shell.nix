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
    cachix
    cfssl
    consul
    consul-template
    dnsutils
    ipcalc
    nixFlakes
    nixfmt
    nixos-rebuild
    nomad
    openssl
    python38Packages.pyhcl
    sops
    ssm-session-manager-plugin
    terraform-with-plugins
    vault-bin
  ];
}
