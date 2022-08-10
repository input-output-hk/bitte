{
  mkCluster,
  mkDeploy,
  lib,
  nixpkgs,
  bitte,
}: {
  self, # target flake self
  inputs,
  domain,
  bitteProfile,
  deploySshKey,
  overlays ? [],
  pkgs ? null,
  clusters ? null,
  hydrationProfile ? hydrateModule,
  hydrateModule ? hydrationProfile,
  nomadEnvs ? envs,
  envs ? {},
  jobs ? null,
}:
assert lib.asserts.assertMsg (pkgs == null) (lib.warn ''

  Important! Immediate action required:

  mkBitteStack { pkgs } is instantly removed. It's presence caused hard to debug
  nixpkgs version mismatches.

  Please pass mkBitteStack { overlays } instead.
'' "Gotta do that now. Sorry, my friend."); let
  overlays' = overlays ++ [bitte.overlays.default];
  pkgs = import nixpkgs {
    overlays = overlays';
    system = "x86_64-linux";
    config.allowUnfree = true;
  };

  # Recurse through a directory and evaluate all expressions
  #
  # Directory -> callPackage(s) -> AttrSet
  recursiveCallPackage = rootPath: callPackage: let
    contents = builtins.readDir rootPath;
    toImport = name: type: type == "regular" && lib.hasSuffix ".nix" name;
    fileNames = builtins.attrNames (lib.filterAttrs toImport contents);
    imported =
      lib.forEach fileNames
      (fileName: callPackage (rootPath + "/${fileName}") {});
  in
    lib.foldl' lib.recursiveUpdate {} imported;

  mkNixosConfigurations = clusters:
    lib.pipe clusters [
      (lib.mapAttrsToList (clusterName: cluster:
        lib.mapAttrsToList (name: lib.nameValuePair "${clusterName}-${name}")
        (cluster.coreNodes // cluster.awsAutoScalingGroups)))
      lib.flatten
      lib.listToAttrs
    ];

  # extend package set with deployment specific items
  # TODO: cleanup
  extended-pkgs = pkgs.extend (final: prev: {
    inherit domain;
  });

  readDirRec = path: let
    inherit (builtins) attrNames readDir;
    inherit (lib) pipe filterAttrs flatten;
  in
    pipe path [
      readDir
      (filterAttrs (n: v: v == "directory" || n == "default.nix"))
      attrNames
      (map (name: path + "/${name}"))
      (map (child:
        if (baseNameOf child) == "default.nix"
        then child
        else readDirRec child))
      flatten
    ];
  clusters' = clusters;
in
  lib.foldl' (acc: s: lib.recursiveUpdate acc s) {} [
    rec {
      inherit envs;

      clusters =
        if clusters' != null
        then
          lib.warn ''

            Use of mkBitteStack { cluster } deprecated.
            Use mkBitteStack { bitteProfile } instead.

            Please ask a knowledgeable colleague for refactoring help.
          ''
          mkCluster {
            inherit pkgs self inputs hydrationProfile;
            bitteProfiles = readDirRec clusters';
          }
        else
          mkCluster {
            inherit pkgs self inputs hydrationProfile;
            bitteProfiles = [bitteProfile];
          };

      nixosConfigurations = mkNixosConfigurations clusters;

      checks.x86_64-linux = let
        clusterName = builtins.head (builtins.attrNames clusters);
        tfWorkspaces = lib.mapAttrs' (n: v: lib.nameValuePair "tf-${n}-plan" v.plan) clusters.${clusterName}.tf;
      in
        tfWorkspaces;
    }
    (mkDeploy {inherit self deploySshKey;})
    (lib.optionalAttrs (jobs != null) rec {
      nomadJobs = recursiveCallPackage jobs extended-pkgs.callPackage;
    })
  ]
