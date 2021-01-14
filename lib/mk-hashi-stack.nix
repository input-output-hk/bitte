{ lib }:

{ rootDir
, self
, domain # E.g. "mantis.ws"
, dockerRegistry ? "docker." + domain
, dockerRole ? "developer"
, vaultDockerPasswordKey ? "kv/nomad-cluster/docker-developer-password"
, jobsDir ? rootDir + "/jobs"
, dockerDir ? rootDir + "/docker"
, clustersDir ? rootDir + "/clusters"
}:

let
  inherit (lib) mkClusters mkNixosConfigurations;
  inherit (self.inputs.nixpkgs.lib) genAttrs;
  # extend package set with deployment specifc items
  # prod-pkgs = pkgs.extend( final: prev: {
  #   inherit domain dockerRegistry dockerRole vaultDockerPasswordKey;
  # });

  # Recurse through a directory and evaluate all expressions
  #
  # Directory -> callPackage(s) -> AttrSet
  recursiveCallPackage = rootPath: callPackage:
    let
      contents = builtins.readDir rootPath;
      toImport = name: type: type == "regular" && lib.hasSuffix ".nix" name;
      fileNames = builtins.attrNames (lib.filterAttrs toImport contents);
      imported = lib.forEach fileNames
        (fileName: callPackage (rootPath + "/${fileName}") { });
    in
      lib.foldl' lib.recursiveUpdate { } imported;

  # "Expands" a docker image into a set which allows for docker commands
  # to be easily performed. E.g. ".#dockerImages.$Image.push
  # imageAttrToCommands = key: image: {
  #   inherit image;

  #   id = "${image.imageName}:${image.imageTag}";

  #   push = let
  #     parts = builtins.split "/" image.imageName;
  #     registry = builtins.elemAt parts 0;
  #     repo = builtins.elemAt parts 2;
  #   in pkgs.writeShellScriptBin "push" ''
  #     set -euo pipefail

  #     export dockerLoginDone="''${dockerLoginDone:-}"
  #     export dockerPassword="''${dockerPassword:-}"

  #     if [ -z "$dockerPassword" ]; then
  #       dockerPassword="$(vault kv get -field value ${vaultDockerPasswordKey})"
  #     fi

  #     if [ -z "$dockerLoginDone" ]; then
  #       echo "$dockerPassword" | docker login docker.mantis.ws -u ${dockerRole} --password-stdin
  #       dockerLoginDone=1
  #     fi

  #     echo -n "Pushing ${image.imageName}:${image.imageTag} ... "

  #     if curl -s "https://developer:$dockerPassword@${registry}/v2/${repo}/tags/list" | grep "${image.imageTag}" &> /dev/null; then
  #       echo "Image already exists in registry"
  #     else
  #       docker load -i ${image}
  #       docker push ${image.imageName}:${image.imageTag}
  #     fi
  #   '';

  #   load = builtins.trace key (pkgs.writeShellScriptBin "load" ''
  #     set -euo pipefail
  #     echo "Loading ${image} (${image.imageName}:${image.imageTag}) ..."
  #     docker load -i ${image}
  #   '');
  # };

  # push-docker-images = { writeShellScriptBin, dockerImages }:
  #   writeShellScriptBin "push-docker-images" ''
  #     set -euo pipefail

  #     ${lib.concatStringsSep "\n"
  #     (lib.mapAttrsToList (key: value: "source ${value.push}/bin/push")
  #       dockerImages)}
  #   '';

  # load-docker-images = { writeShellScriptBin, dockerImages }:
  #   writeShellScriptBin "load-docker-images" ''
  #     set -euo pipefail

  #     ${lib.concatStringsSep "\n"
  #     (lib.mapAttrsToList (key: value: "source ${value.load}/bin/load")
  #       dockerImages)}
  #   '';

in

# lib.makeScope pkgs.newScope (self: with self;
{
  inherit rootDir;

  # nomadJobs = recursiveCallPackage jobsDir prod-pkgs.callPackage;

  # dockerImages =
  #   let
  #     images = recursiveCallPackage dockerDir prod-pkgs.callPackages;
  #   in lib.mapAttrs imageAttrToCommands images;

  # push-docker-images = callPackage push-docker-images { };

  # load-docker-images = callPackage load-docker-images { };

  # clusters = lib.mkClusters {
  #   root = (rootDir + "/clusters");
  #   self = flake;
  #   # inherit (pkgs.hostPlatform) system;
  # };

  clusters = genAttrs [ "x86_64-linux" "x86_64-darwin" ] (system:
  mkClusters {
      root = clustersDir;
      inherit self system;
    });

  nixosConfigurations = lib.mkNixosConfigurations self.clusters.x86_64-darwin;
}
# )
