{
  lib,
  terralib,
}: let
  inherit (terralib) var;
in rec {
  # traverseFiles :: Path -> [ Path ]
  # Recurses a directory and returns a flat list of all file paths
  #
  # foo/
  #   bar/
  #     baz.txt
  #     bat.txt
  #
  # traverseFiles ./foo
  # => [ "bar/baz.txt" "bar/bat.txt" ]
  traverseFiles = dir:
    map
    (s: lib.removePrefix "${toString dir}/" (toString s))
    (lib.filesystem.listFilesRecursive dir);

  # Like traverseFiles, but will only retain files ending in `.enc{,.yaml,.json}`
  sopsFiles = dir:
    lib.filter (name: let
      isJSON = lib.hasSuffix ".enc.json" name;
      isYAML = lib.hasSuffix ".enc.yaml" name;
      isRaw = lib.hasSuffix ".enc" name;
    in
      isJSON || isYAML || isRaw)
    (traverseFiles dir);

  # Like traverseFiles, but will only retain files ending in `{,.toml,.json}`
  dataFiles = dir:
    lib.filter (name: let
      isJSON = lib.hasSuffix ".json" name;
      isTOML = lib.hasSuffix ".toml" name;
    in
      isJSON || isTOML)
    (traverseFiles dir);

  # normalizeTfName :: String -> String
  # Replaces all instances of "/", "-", "." with an underscore
  normalizeTfName = lib.replaceStrings ["/" "-" "."] ["_" "_" "_"];

  # Sanitize names for usage with tf resource names
  #
  # sanitizeFile "foo/bar/secrets.enc.yaml"
  # => "foo_bar_secrets"
  sanitizeFile = path:
    normalizeTfName (lib.removeSuffix ".enc" (lib.removeSuffix ".yaml" (lib.removeSuffix ".json" (toString path))));

  # Sanitize sops file paths for usage with vault
  #
  # sanitizeKvPath "foo/bar/secrets.enc.yaml"
  # => "foo/bar/secrets"
  sanitizeKvPath = path:
    lib.removeSuffix ".enc" (lib.removeSuffix ".yaml" (lib.removeSuffix ".json" (toString path)));

  # Creates the two relevant sops sections used by terraform to provision secrets
  #
  # encrypted/
  #   infra/
  #     postgres.enc.yaml
  #     traefik-users.enc
  #
  # mkVaultResources { dir = ./encrypted; }
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
  # For use with hydrate-app: (nix/cloud/hydrationProfile.nix)
  #
  #  # application state
  #  # --------------
  #  tf.hydrate-app.configuration = let
  #    vault = {
  #      dir = ./. + "/kv/vault";
  #      prefix = "kv/nomad-cluster";
  #    };
  #    consul = {
  #      dir = ./. + "/kv/consul";
  #      prefix = "/";
  #    };
  #    sopsFile = sopsFiles (./. + "${folder.vault}");
  #    vault = bittelib.mkVaultResources {
  #      inherit (vault) dir prefix;
  #    };
  #    consul = bittelib.mkConsulResources {
  #      inherit (consul) dir prefix;
  #    };
  #  in {
  #    data = {inherit (vault) sops_file;};
  #    resource = {
  #      inherit (vault) vault_generic_secret;
  #      inherit (consul) consul_keys;
  #    };
  #  };
  #
  #  Then run as:
  #  $ nix run .#clusters.<cluster>.tf.hydrate-app.plan
  #  $ nix run .#clusters.<cluster>.tf.hydrate-app.apply
  mkVaultResources = {
    dir,
    prefix,
  }: let
    sopsFileList = sopsFiles dir;
    mkDataJson = path: resourceName:
      if lib.hasSuffix ".enc.yaml" path
      then var "jsonencode(yamldecode(data.sops_file.${resourceName}.raw))"
      else if lib.hasSuffix ".enc.json" path
      then var "data.sops_file.${resourceName}.raw"
      else var "jsonencode(data.sops_file.${resourceName})";
  in {
    sops_file =
      lib.listToAttrs
      (builtins.map
        (path:
          lib.nameValuePair (sanitizeFile path) (
            {source_file = builtins.toPath "${dir}/${path}";}
            // lib.optionalAttrs (lib.hasSuffix ".enc" path) {
              input_type = "raw";
            }
          ))
        sopsFileList);
    vault_generic_secret =
      lib.listToAttrs
      (builtins.map
        (path: let
          resourceName = sanitizeFile path;
        in
          lib.nameValuePair resourceName {
            path = ''${prefix}/${sanitizeKvPath path}'';
            data_json = mkDataJson path resourceName;
          })
        sopsFileList);
  };
  mkConsulResources = {
    dir,
    prefix,
  }: let
    dataFileList = dataFiles dir;
    mkDataJson = path:
      if lib.hasSuffix ".toml" path
      then builtins.toJSON (builtins.fromTOML (builtins.readFile (dir + "/${path}")))
      else if lib.hasSuffix ".json" path
      then builtins.readFile (dir + "/${path}")
      else
        throw ''

          bitte/lib.nix:mkConsulResources:
          - only .toml or .json supported
          - got: ${path}
        '';
  in {
    consul_keys =
      lib.listToAttrs
      (builtins.map
        (path: let
          resourceName = sanitizeFile path;
        in
          lib.nameValuePair resourceName {
            key.path = ''${prefix}/${sanitizeKvPath path}'';
            key.value = mkDataJson path;
            key.delete = true;
          })
        dataFileList);
  };
}
