{ pkgs }:
with pkgs;
mkShellNoCC {
  # TF_LOG = "TRACE";

  LOG_LEVEL = "debug";

  buildInputs = [
    age
    agenix-cli
    awscli
    bitte
    cfssl
    consul
    consul-template
    dnsutils
    hydra-provisioner
    ipcalc
    jq
    nixfmt
    nomad
    openssl
    sops
    terraform-with-plugins
    vault-bin
  ];
}
