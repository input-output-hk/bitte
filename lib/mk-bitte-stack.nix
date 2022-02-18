{ mkCluster, mkDeploy, lib, nixpkgs, bitte }:

{ self # target flake self
, inputs
, domain
, bitteProfile
, deploySshKey
, overlays ? [ ]
, pkgs ? null
, clusters ? null
, hydrationProfile ? hydrateModule
, hydrateModule ? hydrationProfile
, nomadEnvs ? envs
, envs ? nomadEnvs
, jobs ? null
, docker ? null
, dockerRegistry ? "docker." + domain
, dockerRole ? "developer"
}:

assert lib.asserts.assertMsg (pkgs == null) (lib.warn ''

Important! Immediate action required:

mkBitteStack { pkgs } is instantly removed. It's presence caused hard to debug
nixpkgs version mismatches.

Please pass mkBitteStack { overlays } instead.
'' "Gotta do that now. Sorry, my friend.");

let
  overlays' = overlays ++ [bitte.overlay];
  pkgs = import nixpkgs {
    overlays = overlays';
    system = "x86_64-linux";
    config.allowUnfree = true;
  };

  # a contract fulfilled by `tf.hydrate`
  vaultDockerPasswordKey = "kv/nomad-cluster/docker-developer-password";

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
    in lib.foldl' lib.recursiveUpdate { } imported;

  # "Expands" a docker image into a set which allows for docker commands
  # to be easily performed. E.g. ".#dockerImages.$Image.push
  imageAttrToCommands = key: image:
    let id = "${image.imageName}:${image.imageTag}";
    in {
      inherit id image;

      # Turning this attribute set into a string will return the outPath instead.
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
          dockerPassword="$(vault kv get -field password ${vaultDockerPasswordKey})"
        fi

        if [ -z "$dockerLoginDone" ]; then
          echo "$dockerPassword" | docker login ${registry} -u ${dockerRole} --password-stdin
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

      load = pkgs.writeShellScriptBin "load" ''
        set -euo pipefail
        echo "Loading ${image} (${image.imageName}:${image.imageTag}) ..."
        docker load -i ${image}
      '';
    };

  push-docker-images' = { writeShellScriptBin, dockerImages }:
    writeShellScriptBin "push-docker-images" ''
      set -euo pipefail

      ${lib.concatStringsSep "\n"
      (lib.mapAttrsToList (key: value: "source ${value.push}/bin/push")
        dockerImages)}
    '';

  load-docker-images' = { writeShellScriptBin, dockerImages }:
    writeShellScriptBin "load-docker-images" ''
      set -euo pipefail

      ${lib.concatStringsSep "\n"
      (lib.mapAttrsToList (key: value: "source ${value.load}/bin/load")
        dockerImages)}
    '';

  mkNixosConfigurations = clusters:
    lib.pipe clusters [
      (lib.mapAttrsToList (clusterName: cluster:
        lib.mapAttrsToList (name: lib.nameValuePair "${clusterName}-${name}")
        (cluster.coreNodes // cluster.awsAutoScalingGroups)))
      lib.flatten
      lib.listToAttrs
    ];

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
          inherit (t) name;
          path = writeText t.name t.tmpl;
        }))
      ];
    in linkFarm "consul-templates" sources;

  # extend package set with deployment specifc items
  # TODO: cleanup
  extended-pkgs = pkgs.extend (final: prev: {
    inherit domain dockerRegistry dockerRole vaultDockerPasswordKey;
  });

  readDirRec = path:
    let
      inherit (builtins) attrNames readDir;
      inherit (lib) pipe filterAttrs flatten;
    in pipe path [
      readDir
      (filterAttrs (n: v: v == "directory" || n == "default.nix"))
      attrNames
      (map (name: path + "/${name}"))
      (map (child:
        if (baseNameOf child) == "default.nix" then
          child
        else
          readDirRec child))
      flatten
    ];
  clusters' = clusters;

in rec {

  inherit envs;

  clusters = if clusters' != null
    then lib.warn ''

    Use of mkBitteStack { cluster } deprecated.
    Use mkBitteStack { bitteProfile } instead.

    Please ask a knowledgeable colleague for refactoring help.
    '' mkCluster {
      inherit pkgs self inputs hydrationProfile;
      bitteProfiles = readDirRec clusters';
    }
    else mkCluster {
      inherit pkgs self inputs hydrationProfile;
      bitteProfiles = [ bitteProfile ];
    };

  nixosConfigurations = mkNixosConfigurations clusters;

  hydraJobs.x86_64-linux = let
    nixosConfigurations' =
      lib.mapAttrs (_: { config, ... }: config.system.build.toplevel)
      nixosConfigurations;
  in nixosConfigurations' // {
    required = pkgs.mkRequired nixosConfigurations';
  };

} // (mkDeploy { inherit self deploySshKey; })
// lib.optionalAttrs (jobs != null) rec {
  nomadJobs = recursiveCallPackage jobs extended-pkgs.callPackage;
  consulTemplates =
    pkgs.callPackage buildConsulTemplates { inherit nomadJobs; };
} // lib.optionalAttrs (docker != null) rec {
  dockerImages =
    let images = recursiveCallPackage docker extended-pkgs.callPackages;
    in lib.mapAttrs imageAttrToCommands images;
  push-docker-images =
    pkgs.callPackage push-docker-images' { inherit dockerImages; };
  load-docker-images =
    pkgs.callPackage load-docker-images' { inherit dockerImages; };
}

