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
    bitte-ruby
    bitte-ruby.wrappedRuby
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
    ssm-session-manager-plugin
    terraform-with-plugins
    vault-bin
  ];
}
