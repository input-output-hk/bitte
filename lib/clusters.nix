{ mkSystem, lib }:

{ self # target flake's 'self'
, inputs, pkgs, clusterFiles, hydrateModule }:

lib.listToAttrs (lib.forEach clusterFiles (file:
  let
    _proto = (mkSystem {
      inherit pkgs self inputs;
      modules = [ file hydrateModule ];
    }).bitteProtoSystem;

    inherit (_proto.config) tf cluster;

    # Separating core and premSim nodes may cause bitte-cli tooling to break.
    # Currently groupings are viewed as core or awsAsg.
    coreAndPremSimNodes =
       let
         inherit (cluster);
         names = map builtins.attrNames [ cluster.coreNodes cluster.premNodes cluster.premSimNodes ];
         combinedNames = builtins.foldl' (s: v:
           s ++ (map (name:
             if (builtins.elem name s) then
               throw "Duplicate node name: ${name}"
             else
               name) v)) [ ] names;
       in builtins.seq combinedNames (cluster.coreNodes // cluster.premSimNodes);

    ourMkSystem = attr: nodeName: coreNode: (mkSystem {
      inherit pkgs self inputs ;
      nodeName = nodeName;
      modules = [ { networking.hostName = lib.mkForce nodeName; } file hydrateModule ]
        ++ coreNode.modules;
    }).${attr};

    awsCoreNodes = lib.mapAttrs (ourMkSystem "bitteAmazonSystem") coreAndPremSimNodes;
    premNodes = lib.mapAttrs (ourMkSystem "bitteProtoSystem") cluster.premNodes;
    coreNodes = awsCoreNodes // premNodes;

    awsAutoScalingGroups = lib.mapAttrs (ourMkSystem "bitteAmazonZfsSystem") cluster.awsAutoScalingGroups;

  in lib.nameValuePair cluster.name {
    inherit _proto tf coreNodes awsAutoScalingGroups;
  }))
