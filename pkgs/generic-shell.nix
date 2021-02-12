{ bitte
, lib
, writeText
, devshell
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
, region
, profile
, terraformOrganization
, nixConf ? null
}: let

in devshell.mkShell {
  bash.extra = ''
    set +e
    export CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/admin 2> /dev/null)"
    export NOMAD_TOKEN="$(vault read -field secret_id nomad/creds/admin 2> /dev/null)"
    set -e
  '';
  # for bitte-cli
  env = {
    LOG_LEVEL = "debug";

    NIX_USER_CONF_FILES = let
      default = writeText "nix.conf" ''
        experimental-features = nix-command flakes ca-references
        substituters = https://cache.nixos.org
        trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
      '';
      in with lib; concatStringsSep ":"
      ((toList default) ++ (optional (nixConf != null) nixConf));

      BITTE_CLUSTER = cluster;
      AWS_PROFILE = profile;
      AWS_DEFAULT_REGION = region;
      VAULT_ADDR = "https://vault.${domain}";
      NOMAD_ADDR = "https://nomad.${domain}";
      CONSUL_HTTP_ADDR = "https://consul.${domain}";
      TERRAFORM_ORGANIZATION = terraformOrganization;
  } // lib.optionalAttrs (caCert != null) {
      CONSUL_CACERT = caCert;
      VAULT_CACERT  = caCert;
  };

  packages = [
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
