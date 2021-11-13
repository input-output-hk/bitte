{ mkSystem
, mkJob
, lib
}:

{ self # target flake's 'self'
, pkgs
, root
}:

let
  readDirRec = path: let
    inherit (builtins) attrNames readDir;
    inherit (lib) pipe filterAttrs flatten;
  in
    pipe path [
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

  clusterFiles = readDirRec root;

in lib.listToAttrs (lib.forEach clusterFiles (file:
  let

    mkJob = mkJob proto;
    tf = proto.config.tf;

    proto = (
      mkSystem {
        inherit pkgs self;
        modules = [ file ];
      }
    ).bitteProtoSystem;

    nodes =
      lib.mapAttrs (nodeName: instance:
        ( mkSystem {
            inherit pkgs self nodeName;
            modules = [ { networking.hostName = lib.mkForce nodeName; } file ] ++ instance.modules;
        } ).bitteAmazonSystem
      ) proto.config.cluster.instances;

    groups =
      lib.mapAttrs (nodeName: instance:
        ( mkSystem {
          inherit pkgs self nodeName;
          modules = [ file ] ++ instance.modules;
        } ).bitteAmazonZfsSystem
      ) proto.config.cluster.autoscalingGroups;

  in lib.nameValuePair proto.config.cluster.name {
    inherit proto tf nodes groups mkJob;
  }))
