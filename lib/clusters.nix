{ mkSystem
, mkJob
, lib
}:

{ self # target flake's 'self'
, inputs
, pkgs
, clusterFiles
}:

lib.listToAttrs (lib.forEach clusterFiles (file:
  let

    mkJob = mkJob proto;
    tf = proto.config.tf;

    proto = (
      mkSystem {
        inherit pkgs self inputs;
        modules = [ file ];
      }
    ).bitteProtoSystem;

    nodes =
      lib.mapAttrs (nodeName: instance:
        ( mkSystem {
            inherit pkgs self inputs nodeName;
            modules = [ { networking.hostName = lib.mkForce nodeName; } file ] ++ instance.modules;
        } ).bitteAmazonSystem
      ) proto.config.cluster.instances;

    groups =
      lib.mapAttrs (nodeName: instance:
        ( mkSystem {
          inherit pkgs self inputs nodeName;
          modules = [ file ] ++ instance.modules;
        } ).bitteAmazonZfsSystem
      ) proto.config.cluster.autoscalingGroups;

  in lib.nameValuePair proto.config.cluster.name {
    inherit proto tf nodes groups mkJob;
  }))
