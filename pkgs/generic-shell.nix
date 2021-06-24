{ bitte
, lib
, writeText
, mkShell
, nixos-rebuild
, terraform-with-plugins
, scaler-guard
, sops
, vault
, openssl
, cfssl
, nixfmt
, awscli
, nomad
, consul
, consul-template
, python38Packages
, direnv
, nixFlakes
, jq }:

{ cluster
, caCert ? null
, domain
, extraEnv ? {}
, extraPackages ? []
, region
, profile
, nixConf ? null
}: let

in mkShell {
  # for bitte-cli
  LOG_LEVEL = "debug";

  NIX_USER_CONF_FILES = let
    default = writeText "nix.conf" ''
        experimental-features = nix-command flakes ca-references recursive-nix
        substituters = https://cache.nixos.org
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
    '';
      in with lib; concatStringsSep ":"
      ((optional (nixConf != null) nixConf) ++ (toList default));

  BITTE_CLUSTER = cluster;
  AWS_PROFILE = profile;
  AWS_DEFAULT_REGION = region;
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
} // lib.optionalAttrs (caCert != null) {
  CONSUL_CACERT = caCert;
  VAULT_CACERT  = caCert;
} // extraEnv
