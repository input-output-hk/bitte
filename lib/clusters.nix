{ self, nixpkgs, system, root }:
let
  inherit (builtins) attrNames readDir mapAttrs;
  inherit (nixpkgs.lib)
    flip pipe mkForce filterAttrs flatten listToAttrs forEach nameValuePair
    mapAttrs' nixosSystem;

  readDirRec = path:
    pipe path [
      builtins.readDir
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

  mkSystem = nodeName: modules:
    nixosSystem {
      # NOTE In the domain of possibilities that we currently care for, a NixOS
      # system would *always* be "x86_64-linux". In contrast, the *deployer* can
      # be at least x86_64-linux, x86_64-darwin, with Apple Silicon poised to
      # complicate things even further in the not-so-distant future.
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ self.overlay ];
      };
      modules = [
        ../modules
        (nixpkgs + "/nixos/modules/virtualisation/amazon-image.nix")
      ] ++ modules;
      specialArgs = { inherit nodeName self deployerPkgs; };
    };

  deployerPkgs = import nixpkgs {
    inherit system;
    overlays = [ self.overlay ];
  };

  mkProto = file: nixosSystem {
    inherit system;
    pkgs = deployerPkgs;
    modules = [
      ../modules/default.nix
      ../profiles/nix.nix
      ../profiles/consul/policies.nix
      file
    ];
    specialArgs = { inherit self deployerPkgs; };
  };

  clusterFiles = readDirRec root;

  mkCluster = file:
  let
    proto = mkProto file;

    bitte-secrets = deployerPkgs.callPackage ../pkgs/bitte-secrets.nix {
      inherit (proto.config) cluster;
    };

    mkNode = name: instance: mkSystem name
    ([ { networking.hostName = mkForce name; } file ] ++ instance.modules);

    mkGroup = name: instance: mkSystem name ([ file ] ++ instance.modules);
  in rec {
    inherit proto bitte-secrets;

    tf = proto.config.tf;

    nodes = mapAttrs mkNode proto.config.cluster.instances;

    groups = mapAttrs mkGroup proto.config.cluster.autoscalingGroups;

    # All data used by the CLI should be exported here.
    topology = {
      nodes = flip mapAttrs proto.config.cluster.instances (name: node: {
        inherit (proto.config.cluster) kms region;
        inherit (node) name privateIP instanceType;
      });
      groups = attrNames groups;
    };

    mkJob = import ./mk-job.nix proto;
  } // bitte-secrets;

  mkClusters = flip pipe [
    (map mkCluster)
    (map (c: nameValuePair c.proto.config.cluster.name c))
    listToAttrs
  ];

  clusters = mkClusters clusterFiles;
in clusters
