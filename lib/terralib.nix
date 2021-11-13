{ nixpkgs
, lib
}:
let
  inherit (builtins) attrValues fromJSON toJSON trace mapAttrs genList foldl';
in
rec {
  amis = import (nixpkgs + "/nixos/modules/virtualisation/ec2-amis.nix");

  var = v: "\${${v}}";
  id = v: var "${v}.id";
  pp = v: trace (toJSON v) v;

  readJSON = file: fromJSON (lib.fileContents file);
  sops2kms = file: (lib.elemAt (readJSON file).sops.kms 0).arn;
  sops2region = file: lib.elemAt (lib.splitString ":" (sops2kms file)) 3;

  cidrsOf = lib.mapAttrsToList (_: subnet: subnet.cidr);

  awsProviderNameFor = region: lib.replaceStrings [ "-" ] [ "_" ] region;
  awsProviderFor = region: "aws.${awsProviderNameFor region}";

  merge = lib.foldl' lib.recursiveUpdate { };

  nullRoute = {
    egress_only_gateway_id = null;
    instance_id = null;
    ipv6_cidr_block = null;
    local_gateway_id = null;
    nat_gateway_id = null;
    network_interface_id = null;
    transit_gateway_id = null;
    vpc_peering_connection_id = null;
    gateway_id = null;
    vpc_endpoint_id = null;
  };

  vpcs = cluster:
    lib.forEach (builtins.attrValues cluster.autoscalingGroups)
    (asg: asg.vpc);

  mapVpcs = cluster: f:
    lib.listToAttrs (lib.flatten (lib.forEach (vpcs cluster) f));

  mapVpcsToList = cluster: lib.forEach (vpcs cluster);

  regions = [
    # "ap-east-1"
    "ap-northeast-1"
    "ap-northeast-2"
    "ap-south-1"
    "ap-southeast-1"
    "ap-southeast-2"
    "ca-central-1"
    "eu-central-1"
    "eu-north-1"
    "eu-west-1"
    "eu-west-2"
    "eu-west-3"
    # "me-south-1"
    "sa-east-1"
    "us-east-1"
    "us-east-2"
    "us-west-1"
    "us-west-2"
  ];

  mkSecurityGroupRule = ({ region, prefix, rule, protocol }:
    let
      common = {
        provider = awsProviderFor region;
        type = rule.type;
        from_port = rule.from;
        to_port = rule.to;
        protocol = protocol;
        security_group_id = rule.securityGroupId;
      };

      from-self = (lib.nameValuePair
        "${prefix}-${rule.type}-${protocol}-${rule.name}-self"
        (common // { self = true; }));

      from-cidr = (lib.nameValuePair
        "${prefix}-${rule.type}-${protocol}-${rule.name}-cidr"
        (common // { cidr_blocks = lib.unique rule.cidrs; }));

      from-ssgi = (lib.nameValuePair
        "${prefix}-${rule.type}-${protocol}-${rule.name}-ssgi" (common // {
          source_security_group_id = rule.sourceSecurityGroupId;
        }));

    in (lib.optional (rule.self != false) from-self)
    ++ (lib.optional (rule.cidrs != [ ]) from-cidr)
    ++ (lib.optional (rule.sourceSecurityGroupId != null) from-ssgi));
}

