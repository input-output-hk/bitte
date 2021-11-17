{ mkCluster
, lib
}:

{ flake
, domain
, clusters
, jobs ? null
, docker ? null
, dockerRegistry ? "docker." + domain, dockerRole ? "developer"
, vaultDockerPasswordKey ? "kv/nomad-cluster/docker-developer-password"
}:

let
  inherit (flake.inputs) nixpkgs;

  pkgs = nixpkgs.legacyPackages.x86_64-linux.extend flake.overlay;

  # extend package set with deployment specifc items
  prod-pkgs = pkgs.extend (final: prev: {
    inherit domain dockerRegistry dockerRole vaultDockerPasswordKey;
  });

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
          dockerPassword="$(vault kv get -field value ${vaultDockerPasswordKey})"
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

  push-docker-images = { writeShellScriptBin, dockerImages }:
    writeShellScriptBin "push-docker-images" ''
      set -euo pipefail

      ${lib.concatStringsSep "\n"
      (lib.mapAttrsToList (key: value: "source ${value.push}/bin/push")
        dockerImages)}
    '';

  load-docker-images = { writeShellScriptBin, dockerImages }:
    writeShellScriptBin "load-docker-images" ''
      set -euo pipefail

      ${lib.concatStringsSep "\n"
      (lib.mapAttrsToList (key: value: "source ${value.load}/bin/load")
        dockerImages)}
    '';

  mkNixosConfigurations = clusters:
    lib.pipe clusters [
      (lib.mapAttrsToList (clusterName: cluster:
        lib.mapAttrsToList
        (name: value: lib.nameValuePair "${clusterName}-${name}" value)
        (cluster.nodes // cluster.groups)))
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
          name = t.name;
          path = writeText t.name t.tmpl;
        }))
      ];
    in linkFarm "consul-templates" sources;

in lib.makeScope pkgs.newScope (self:
  with self; {

    clusters = mkCluster { inherit pkgs; root = clusters; self = flake; };
    nixosConfigurations = mkNixosConfigurations self.clusters;

    consulTemplates = callPackage buildConsulTemplates { };

    hydraJobs.x86_64-linux = let
      nixosConfigurations =
        lib.mapAttrs (_: { config, ... }: config.system.build.toplevel)
        self.nixosConfigurations;
    in nixosConfigurations // {
      required = pkgs.mkRequired nixosConfigurations;
    };
  } // lib.optionalAttrs (jobs != null) {
    nomadJobs = recursiveCallPackage (jobs) prod-pkgs.callPackage;
  } // lib.optionalAttrs (docker != null) {
    dockerImages = let
      images = recursiveCallPackage (docker) prod-pkgs.callPackages;
    in lib.mapAttrs imageAttrToCommands images;
    push-docker-images = callPackage push-docker-images { };
    load-docker-images = callPackage load-docker-images { };
  }
)

