{
  mkSystem,
  lib,
}: {
  self, # target flake's 'self'
  inputs,
  pkgs,
  bitteProfiles,
  hydrationProfile,
}:
lib.listToAttrs (lib.forEach bitteProfiles (bitteProfile: let
  _proto =
    (mkSystem {
      inherit pkgs self inputs;
      modules = [bitteProfile hydrationProfile];
    })
    .bitteProtoSystem;

  inherit (_proto.config) tf cluster;

  # Separating core and premSim nodes may cause bitte-cli tooling to break.
  # Currently groupings are viewed as core or awsAsg.
  coreAndPremSimNodes = let
    inherit (cluster);
    names = map builtins.attrNames [cluster.coreNodes cluster.premNodes cluster.premSimNodes];
    combinedNames = builtins.foldl' (s: v:
      s
      ++ (map (name:
        if (builtins.elem name s)
        then throw "Duplicate node name: ${name}"
        else name)
      v)) []
    names;
  in
    builtins.deepSeq combinedNames (cluster.coreNodes // cluster.premSimNodes);

  coreModules = nodeName: [bitteProfile hydrationProfile {networking.hostName = lib.mkForce nodeName;}];
  asgModules = nodeName: [bitteProfile hydrationProfile];

  ourMkSystem = systemType: baseModules: nodeName: node:
    (mkSystem {
      inherit self inputs nodeName;
      pkgs = node.pkgs or pkgs;
      modules = (baseModules nodeName) ++ node.modules;
    })
    .${systemType};

  awsCoreNodes = lib.mapAttrs (ourMkSystem "bitteAmazonSystem" coreModules) coreAndPremSimNodes;
  premNodes = lib.mapAttrs (ourMkSystem "bitteProtoSystem" coreModules) cluster.premNodes;
  coreNodes = awsCoreNodes // premNodes;

  awsAutoScalingGroups = lib.mapAttrs (ourMkSystem "bitteAmazonZfsSystem" asgModules) cluster.awsAutoScalingGroups;
in
  lib.nameValuePair cluster.name {
    inherit _proto tf coreNodes awsAutoScalingGroups;
  }))
