{ lib
, terralib
}:

{
  # traverseFiles :: Path -> [ Path ]
  # Recurses a directory and returns a flat list of all file paths
  #
  # foo/
  #   bar/
  #     baz.txt
  #     bat.txt
  #
  # travervseFiles ./foo
  # => [ "bar/baz.txt" "bar/bat.txt" ]
  traverseFiles = topDir: let
    dirItems = dir: let
      dir' = builtins.readDir dir;
    in
      lib.mapAttrsFlatten (
        name: type:
        if type == "directory"
          then
            lib.flatten (builtins.map (x: "${name}/${x}") (dirItems "${dir}/${name}"))
          else
            name
      )
      dir';
  in lib.flatten (dirItems topDir);

  # Like traverseFiles, but will only retain files ending in `.enc{,.yaml,.json}`
  sopsFiles = dir: lib.filter (name: let
      isJSON = lib.hasSuffix ".enc.json" name;
      isYAML = lib.hasSuffix ".enc.yaml" name;
      isRaw = lib.hasSuffix ".enc" name;
    in isJSON || isYAML || isRaw)
    (traverseFiles dir);

  # normalizeTfName :: String -> String
  # Replaces all instances of "/", "-", "." with an underscore
  normalizeTfName = lib.replaceStrings [ "/" "-" "." ] [ "_" "_" "_" ];

  # Sanitize names for usage with tf resource names
  #
  # sanitizeSecretsFile "foo/bar/secrets.enc.yaml"
  # => "foo_bar_secrets"
  sanitizeSecretsFile = path:
    normalizeTfName (lib.removeSuffix ".enc" (lib.removeSuffix ".yaml" (lib.removeSuffix ".json" (toString path))));

  # Sanitize sops file paths for usage with vault
  #
  # sanitizeKvSopsPath "foo/bar/secrets.enc.yaml"
  # => "foo/bar/secrets"
  sanitizeKvSopsPath = path:
    lib.removeSuffix ".enc" (lib.removeSuffix ".yaml" (lib.removeSuffix ".json" (toString path)));

  # Creates the two relevant sops sections used by terraform to provision secrets
  #
  # encrypted/
  #   infra/
  #     postgres.enc.yaml
  #     traefik-users.enc
  #
  # mkSopsConfig { dir = ./encrypted; }
  # => {
  #   sops_file = {
  #     infra_postgres = {
  #       source_file = "/nix/store/abc.../postrges.enc.yaml";
  #     };
  #     traefik_users = {
  #       input_type = "raw";
  #       source_file = "/nix/store/abc.../traefik-users.enc.yaml";
  #     };
  #   };
  #   vault_generic_secret = {
  #     infra_postgres = {
  #       data_json = "${jsonencode(yamldecode(data.sops_file.infra_postgres.raw))}";
  #       path = "kv/nomad-cluster/infra/postgres";
  #     };
  #     traefik_users = { ... };
  #   };
  # }
  #
  # For use with hydrate-secrets:
  #     # nix/cloud/hydrationProfile.nix
  #     tf.hydrate-secrets.configuration = let
  #       inherit (bitte.lib) mkSopsConfig;
  #       sopsConfig = mkSopsConfig { dir = "${./.}/${secretsFolder}"; };
  #     in {
  #       data.sops_file = sopsConfig.sops_file;
  #       resource.vault_generic_secret = sopsConfig.vault_generic_secret;
  #     };
  #
  #  Then run as:
  #  $ nix run .#clusters.<cluster>.tf.hydrate-secrets.plan
  #  $ nix run .#clusters.<cluster>.tf.hydrate-secrets.apply
  mkSopsConfig = { dir, vaultPrefix ? "kv/nomad-cluster" }: let
    sopsFileList = sopsFiles dir;
    mkDataJson = path: resourceName:
      if lib.hasSuffix ".enc.yaml" path
      then var "jsonencode(yamldecode(data.sops_file.${resourceName}.raw))"
      else if lib.hasSuffix ".enc.json" path
      then var "data.sops_file.${resourceName}.raw"
      else var "jsonencode(data.sops_file.${resourceName})";
  in {
    sops_file = lib.listToAttrs
      (builtins.map
      (path: lib.nameValuePair (sanitizeSecretsFile path) (
        { source_file = builtins.toPath "${dir}/${path}";}
        // lib.optionalAttrs (lib.hasSuffix ".enc" path) {
          input_type = "raw";
        }
      ))
      sopsFileList);
    vault_generic_secret = lib.listToAttrs
      (builtins.map
        (path: let
          resourceName = sanitizeSecretsFile path;
        in lib.nameValuePair resourceName {
            path = ''${vaultPrefix}/${sanitizeKvSopsPath path}'';
            data_json = mkDataJson path resourceName;
          })
      sopsFileList);
  };
}

