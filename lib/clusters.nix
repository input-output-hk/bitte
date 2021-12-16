{ mkSystem, lib }:

{ self # target flake's 'self'
, inputs, pkgs, clusterFiles, hydrateModule }:

lib.listToAttrs (lib.forEach clusterFiles (file:
  let
    inherit (_proto.config) tf;

    _proto = (mkSystem {
      inherit pkgs self inputs;
      modules = [ file hydrateModule ];
    }).bitteProtoSystem;

    coreNodes = lib.mapAttrs (nodeName: coreNode:
      (mkSystem {
        inherit pkgs self inputs nodeName;
        modules = [ { networking.hostName = lib.mkForce nodeName; } file hydrateModule ]
          ++ coreNode.modules;
      }).bitteAmazonSystem) _proto.config.cluster.coreNodes;

    awsAutoScalingGroups = lib.mapAttrs (nodeName: awsAutoScalingGroup:
      (mkSystem {
        inherit pkgs self inputs nodeName;
        modules = [ file ] ++ awsAutoScalingGroup.modules;
      }).bitteAmazonZfsSystem) _proto.config.cluster.awsAutoScalingGroups;

  in lib.nameValuePair _proto.config.cluster.name {
    inherit _proto tf coreNodes awsAutoScalingGroups;
  }))
