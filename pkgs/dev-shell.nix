{ pkgs }:
with pkgs;
mkShellNoCC {
  # TF_LOG = "TRACE";

  LOG_LEVEL = "debug";

  buildInputs = [
    awscli
    bitte
    cachix
    cfssl
    consul
    consul-template
    dnsutils
    ipcalc
    jq
    nixfmt
    nixos-rebuild
    nomad
    openssl
    sops
    ssm-session-manager-plugin
    terraform-with-plugins
    vault-bin
    hydra-provisioner
  ];
}
