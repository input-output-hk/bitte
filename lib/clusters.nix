{ mkSystem, lib }:

{ self # target flake's 'self'
, inputs, pkgs, clusterFiles, hydrateModule }:

lib.listToAttrs (lib.forEach clusterFiles (file:
  let
    inherit (proto.config) tf;

    proto = (mkSystem {
      inherit pkgs self inputs;
      modules = [ file hydrateModule ];
    }).bitteProtoSystem;

    nodes = lib.mapAttrs (nodeName: coreNode:
      (mkSystem {
        inherit pkgs self inputs nodeName;
        modules = [ { networking.hostName = lib.mkForce nodeName; } file hydrateModule ]
          ++ coreNode.modules;
      }).bitteAmazonSystem) proto.config.cluster.instances;

    groups = lib.mapAttrs (nodeName: awsAutoScalingGroup:
      (mkSystem {
        inherit pkgs self inputs nodeName;
        modules = [ file ] ++ awsAutoScalingGroup.modules;
      }).bitteAmazonZfsSystem) proto.config.cluster.awsAutoScalingGroups;

  in lib.nameValuePair proto.config.cluster.name {
    inherit proto tf nodes groups;
  }))
