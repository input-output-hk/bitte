{ nixpkgs }:
/* Library of low-level helper functions for nix expressions.
 *
 * Please implement (mostly) exhaustive unit tests
 * for new functions in `./tests.nix'.
 */
let
  lib = nixpkgs.lib.makeExtensible (self:
    let
      callLibs = file: import file { lib = self; };
    in
    {
      inherit nixpkgs;
      clusters = callLibs ./clusters.nix;
      inherit (self.clusters) mkCluster mkClusters;

      mkNixosConfigurations = clusters:
        let
          inherit (nixpkgs.lib) pipe mapAttrsToList nameValuePair flatten listToAttrs;
        in
        pipe clusters [
          (mapAttrsToList (clusterName: cluster:
            mapAttrsToList
              (name: value: nameValuePair "${clusterName}-${name}" value)
              (cluster.nodes // cluster.groups)))
          flatten
          listToAttrs
        ];

      importNixosModules = dir:
        let
          inherit dir;

          inherit (nixpkgs.lib)
            hasSuffix nameValuePair filterAttrs readDir mapAttrs' removeSuffix;

          mapFilterAttrs = sieve: f: attrs: filterAttrs sieve (mapAttrs' f attrs);
          paths = builtins.readDir dir;
        in
        mapFilterAttrs (key: value: value != null)
          (name: type:
            nameValuePair (removeSuffix ".nix" name)
              (if name != "default.nix" && type == "regular" && hasSuffix ".nix" name then
                (import (dir + "/${name}"))
              else
                null))
          paths;
    });
in
lib
