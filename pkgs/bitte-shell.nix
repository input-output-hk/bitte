{ bitte, lib, writeText, mkShell, nixos-rebuild, terraform-with-plugins
, scaler-guard, sops, vault, openssl, cfssl, nixfmt, awscli, nomad, consul
, consul-template, python38Packages, direnv, nixFlakes, jq }:

{ cluster, caCert ? null, domain, extraEnv ? { }, extraPackages ? [ ], region
, profile, namespace ? cluster, nixConfig ? null }:
let

in mkShell ({
  # for bitte-cli
  LOG_LEVEL = "debug";

  NIX_CONFIG = ''
    extra-experimental-features = nix-command flakes ca-references recursive-nix
    extra-substituters = https://hydra.iohk.io
    extra-trusted-public-keys = hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
    bash-prompt = [bitte]
  '' + (lib.optionalString (nixConfig != null) nixConfig);

  BITTE_CLUSTER = cluster;
  AWS_PROFILE = profile;
  AWS_DEFAULT_REGION = region;
  NOMAD_NAMESPACE = namespace;
  VAULT_ADDR = "https://vault.${domain}";
  NOMAD_ADDR = "https://nomad.${domain}";
  CONSUL_HTTP_ADDR = "https://consul.${domain}";

  buildInputs = [
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
  ] ++ extraPackages;
} // (lib.optionalAttrs (caCert != null) {
  CONSUL_CACERT = caCert;
  VAULT_CACERT = caCert;
}) // extraEnv)
