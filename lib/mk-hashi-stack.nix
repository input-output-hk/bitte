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
  inherit (self.inputs.nixpkgs.lib) genAttrs foldl' hasSuffix filterAttrs
  forEach recursiveUpdate concatStringsSep mapAttrsToList mapAttrs makeScope;
  # extend package set with deployment specifc items
  prod-pkgs = import self.inputs.nixpkgs {
    overlays = [
      self.overlay
      (final: prev: {
        inherit domain dockerRegistry dockerRole vaultDockerPasswordKey;
      })
    ];
    system = "x86_64-linux";
  };

  pkgs = import self.inputs.nixpkgs {
    overlays = [
      self.overlay
    ];
    system = "x86_64-darwin";
  };
  # Recurse through a directory and evaluate all expressions
  #
  # Directory -> callPackage(s) -> AttrSet
  recursiveCallPackage = rootPath: callPackage:
    let
      contents = builtins.readDir rootPath;
      toImport = name: type: type == "regular" && hasSuffix ".nix" name;
      fileNames = builtins.attrNames (filterAttrs toImport contents);
      imported = forEach fileNames
        (fileName: callPackage (rootPath + "/${fileName}") { });
    in
      foldl' recursiveUpdate { } imported;

  # "Expands" a docker image into a set which allows for docker commands
  # to be easily performed. E.g. ".#dockerImages.$Image.push
  imageAttrToCommands = key: image: let
     id = "${image.imageName}:${image.imageTag}";
  in {
     inherit id image;

     outPath = id;

     push = let
       parts = builtins.split "/" image.imageName;
       registry = builtins.elemAt parts 0;
       repo = builtins.elemAt parts 2;
     in pkgs.writeShellScriptBin "push" ''
       set -euo pipefail

       export dockerLoginDone="''${dockerLoginDone:-}"
       export dockerPassword="''${dockerPassword:-}"

       if [ -z "$dockerPassword" ]; then
         dockerPassword="$(vault kv get -field value ${vaultDockerPasswordKey})"
       fi

       if [ -z "$dockerLoginDone" ]; then
         echo "$dockerPassword" | docker login docker.mantis.ws -u ${dockerRole} --password-stdin
         dockerLoginDone=1
       fi

       echo -n "Pushing ${image.imageName}:${image.imageTag} ... "

       if curl -s "https://developer:$dockerPassword@${registry}/v2/${repo}/tags/list" | grep "${image.imageTag}" &> /dev/null; then
         echo "Image already exists in registry"
       else
         docker load -i ${image}
         docker push ${image.imageName}:${image.imageTag}
       fi
     '';

     load = builtins.trace key (pkgs.writeShellScriptBin "load" ''
       set -euo pipefail
       echo "Loading ${image} (${image.imageName}:${image.imageTag}) ..."
       docker load -i ${image}
     '');
   };

   push-docker-images = { writeShellScriptBin, dockerImages }:
     writeShellScriptBin "push-docker-images" ''
       set -euo pipefail

       ${concatStringsSep "\n"
       (mapAttrsToList (key: value: "source ${value.push}/bin/push")
         dockerImages)}
     '';

   load-docker-images = { writeShellScriptBin, dockerImages }:
     writeShellScriptBin "load-docker-images" ''
       set -euo pipefail

       ${concatStringsSep "\n"
       (mapAttrsToList (key: value: "source ${value.load}/bin/load")
         dockerImages)}
     '';

  buildConsulTemplates = { nomadJobs, writeText, linkFarm }:
    let
      sources = lib.pipe nomadJobs [
        (lib.filterAttrs (n: v: v ? evaluated))
        (lib.mapAttrsToList (n: v: {
          path = [ n v.evaluated.Job.Namespace ];
          taskGroups = v.evaluated.Job.TaskGroups;
        }))
        (map (e:
          map (tg:
            map (t:
              if t.Templates != null then
                map (tpl: {
                  name = lib.concatStringsSep "/"
                    (e.path ++ [ tg.Name t.Name tpl.DestPath ]);
                  tmpl = tpl.EmbeddedTmpl;
                }) t.Templates
              else
                null) tg.Tasks) e.taskGroups))
        builtins.concatLists
        builtins.concatLists
        (lib.filter (e: e != null))
        builtins.concatLists
        (map (t: {
          name = t.name;
          path = writeText t.name t.tmpl;
        }))
      ];
    in linkFarm "consul-templates" sources;
in
makeScope pkgs.newScope (scope:
  with scope;
{
  inherit rootDir;

  nomadJobs = recursiveCallPackage jobsDir callPackage;

  dockerImages =
    let
      images = recursiveCallPackage dockerDir prod-pkgs.callPackages;
    in mapAttrs imageAttrToCommands images;

  push-docker-images = callPackage push-docker-images { };

  load-docker-images = callPackage load-docker-images { };

  consulTemplates = callPackage buildConsulTemplates { };

  clusters = genAttrs [ "x86_64-linux" "x86_64-darwin" ] (system:
  mkClusters {
      root = clustersDir;
      inherit self system;
    });

  nixosConfigurations = mkNixosConfigurations self.clusters.x86_64-darwin;
})
