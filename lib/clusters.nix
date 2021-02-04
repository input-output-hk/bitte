{ lib }:
let

  inherit (lib) nixpkgs;
  inherit (nixpkgs.lib) nixosSystem mkForce mapAttrs flip attrNames;

  deployerPkgsFor = self: system: import self.inputs.nixpkgs {
    inherit system;
    overlays = [ self.overlay ];
  };

in
rec {

  mkProto = self: deployerPkgs: file:
    nixosSystem {
      inherit (deployerPkgs) pkgs system;
      modules = [
        ../modules/default.nix
        ../profiles/nix.nix
        ../profiles/consul/policies.nix
        file
      ];
      specialArgs = {
        inherit self deployerPkgs;
        inherit (self.inputs) bitte;
      };
    };

  mkCluster = self: deployerPkgs: file:
    let
      proto = mkProto self deployerPkgs file;

      # bitte-secrets = deployerPkgs.callPackage ../pkgs/bitte-secrets.nix {
      #   inherit (proto.config) cluster;
      # };

      mkNode = name: instance: mkSystem self deployerPkgs name
        ([{ networking.hostName = mkForce name; } file] ++ instance.modules);

      mkGroup = name: instance: mkSystem self deployerPkgs name ([ file ] ++ instance.modules);
    in
    rec {
      inherit
      proto
      # bitte-secrets
      ;

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
    }
    # //
    # bitte-secrets
    ;

  mkSystem = self: deployerPkgs: nodeName: modules:
    nixosSystem {
      system = "x86_64-linux";
      pkgs = import self.inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [ self.overlay ];
      };
      modules = [
        ../modules
        (nixpkgs + "/nixos/modules/virtualisation/amazon-image.nix")
      ] ++ modules;
      specialArgs = {
        inherit nodeName self deployerPkgs;
        inherit (self.inputs) bitte;
      };
    };

  mkClusters =
    { self, system, root }:
    let
      inherit (builtins) attrNames readDir mapAttrs;
      inherit (nixpkgs.lib)
        flip pipe mkForce filterAttrs flatten listToAttrs forEach nameValuePair
        mapAttrs' nixosSystem;

      deployerPkgs = deployerPkgsFor self system;
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

      clusterFiles = readDirRec root;

    in
    pipe clusterFiles [
      (map (mkCluster self deployerPkgs))
      (map (c: nameValuePair c.proto.config.cluster.name c))
      listToAttrs
    ];
}
