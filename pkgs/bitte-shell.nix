{ bitte, lib, writeText, mkShell, nixos-rebuild, terraform-with-plugins
, scaler-guard, sops, vault-bin, openssl, cfssl, nixfmt, awscli, nomad, consul
, consul-template, python38Packages, direnv, jq }:

{ self, cluster ? builtins.head (builtins.attrNames self.clusters)
, caCert ? null, domain ? self.clusters.${cluster}.proto.config.cluster.domain
, extraEnv ? { }, extraPackages ? [ ]
, region ? self.clusters.${cluster}.proto.config.cluster.region or ""
, profile ? "", provider ? "AWS", namespace ? cluster, nixConfig ? null }:
let
  asgRegions = lib.attrValues (lib.mapAttrs (_: v: v.region)
    self.clusters.${cluster}.proto.config.cluster.autoscalingGroups);
  asgRegionString =
    lib.strings.replaceStrings [ " " ] [ ":" ] (toString asgRegions);
in mkShell ({
  # for bitte-cli
  LOG_LEVEL = "debug";

  NIX_CONFIG = ''
    extra-experimental-features = nix-command flakes ca-references recursive-nix
    extra-substituters = https://hydra.iohk.io
    extra-trusted-public-keys = hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=
    bash-prompt = \[\033[0;32m\][bitte]:\[\033[m\]\040
  '' + (lib.optionalString (nixConfig != null) nixConfig);

  BITTE_CLUSTER = cluster;
  BITTE_DOMAIN = domain;
  BITTE_PROVIDER = provider;
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
    vault-bin
    openssl
    cfssl
    nixfmt
    awscli
    nomad
    consul
    consul-template
    python38Packages.pyhcl
    direnv
    jq
  ] ++ extraPackages;

  shellHook = ''
    export FLAKE_ROOT=$(git rev-parse --show-toplevel)
    if ! git show HEAD:${"\${cache:=$FLAKE_ROOT/.cache.json}"}; then
      rm -f $cache
      touch $cache
      git reset
      git add $cache
      git commit --no-gpg-sign -m "add empty .cache.json"
      git update-index --assume-unchanged $cache
    fi

  '';
} // (lib.optionalAttrs (caCert != null) {
  CONSUL_CACERT = caCert;
  VAULT_CACERT = caCert;
}) // lib.optionalAttrs (provider == "AWS") {
  AWS_PROFILE = profile;
  AWS_DEFAULT_REGION = region;
  AWS_ASG_REGIONS = asgRegionString;
} // extraEnv)
