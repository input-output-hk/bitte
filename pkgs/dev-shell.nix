{ pkgs }:
with pkgs;
mkShell.override { stdenv = stdenvNoCC; } {
  # TF_LOG = "TRACE";

  LOG_LEVEL = "debug";

  buildInputs = [
    awscli
    bitte
    cfssl
    consul
    consul-template
    dnsutils
    ipcalc
    jq
    nixfmt
    nomad
    openssl
    sops
    ssm-session-manager-plugin
    terraform-with-plugins
    vault-bin
    hydra-provisioner
  ];
}
