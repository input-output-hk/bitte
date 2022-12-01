{
  nixpkgs,
  lib,
}: let
  renamed = old: new:
    lib.warn ''
      RENAMED:
        terralib.${old} -> terralib.${new}
    '';
  nullRoute' = {
    egress_only_gateway_id = null;
    instance_id = null;
    local_gateway_id = null;
    nat_gateway_id = null;
    network_interface_id = null;
    transit_gateway_id = null;
    vpc_peering_connection_id = null;
    gateway_id = null;
    vpc_endpoint_id = null;
  };
in rec {
  amis = import (nixpkgs + "/nixos/modules/virtualisation/ec2-amis.nix");

  var = v: "\${${v}}";
  id = v: var "${v}.id";
  pp = v: builtins.trace (builtins.toJSON v) v;

  awsProviderNameFor = lib.replaceStrings ["-"] ["_"];
  awsProviderFor = region: "aws.${awsProviderNameFor region}";

  nullRouteInline = nullRoute' // {ipv6_cidr_block = null;};

  nullRoute = nullRoute' // {destination_ipv6_cidr_block = null;};

  # Common ssh args used in TF provisioning scripts
  sshArgs = "-C -oConnectTimeout=5 -oUserKnownHostsFile=/dev/null -oNumberOfPasswordPrompts=0 -oServerAliveInterval=60 -oControlPersist=600 -oStrictHostKeyChecking=no";

  aws = {
    # asgVpcs returns a vpc attr struct when provided config.cluster.
    # Example attr struct:
    #  [
    #    {
    #      "cidr": "10.24.0.0/16",
    #      "id": "${data.aws_vpc.bitte-world-eu-central-1-asgs.id}",
    #      "name": "bitte-world-eu-central-1-asgs",
    #      "region": "eu-central-1",
    #      "subnets": {
    #        "a": {
    #          "availabilityZone": "${element(module.instance_types_to_azs_eu-central-1.availability_zones, 0)}",
    #          "cidr": "10.24.0.0/18",
    #          "id": "${aws_subnet.a.id}",
    #          "name": "a"
    #        },
    #        "b": {
    #          "availabilityZone": "${element(module.instance_types_to_azs_eu-central-1.availability_zones, 1)}",
    #          "cidr": "10.24.64.0/18",
    #          "id": "${aws_subnet.b.id}",
    #          "name": "b"
    #        },
    #        "c": {
    #          "availabilityZone": "${element(module.instance_types_to_azs_eu-central-1.availability_zones, 2)}",
    #          "cidr": "10.24.128.0/18",
    #          "id": "${aws_subnet.c.id}",
    #          "name": "c"
    #        }
    #      }
    #    },
    #    ...
    #  ]
    asgVpcs = cluster:
      lib.forEach (builtins.attrValues cluster.awsAutoScalingGroups) (asg: asg.vpc);

    mapAsgVpcs = cluster: f:
      lib.listToAttrs (lib.flatten (lib.forEach (aws.asgVpcs cluster) f));

    mapAsgVpcsToList = cluster: lib.forEach (aws.asgVpcs cluster);
  };
  asgVpcs = renamed "asgVpcs" "aws.asgVpcs" aws.asgVpcs;
  mapAsgVpcs = renamed "mapAsgVpcs" "aws.mapAsgVpcs" aws.mapAsgVpcs;
  mapAsgVpcsToList = renamed "mapAsgVpcsToList" "aws.mapAsgVpcsToList" aws.mapAsgVpcsToList;

  # "a/b/c/d" => [ "" "/a" "/a/b" "/a/b/c" "/a/b/c/d" ]
  pathPrefix = rootDir: dir: let
    fullPath = "${rootDir}/${dir}";
    splitPath = lib.splitString "/" fullPath;
    cascade =
      lib.foldl' (s: v: let
        p = "${s.path}${v}/";
      in {
        acc = s.acc ++ [p];
        path = p;
      }) {
        acc = [""];
        path = "";
      }
      splitPath;
    # Ensure that any "/dir1/dir2/*/" entries don't exist
    # as this doesn't make allowance for nested subdirs.
    allowWildcard = map (p:
      if lib.hasSuffix "/*/" p
      then (lib.removeSuffix "/" p)
      else p);
  in
    allowWildcard cascade.acc;

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

  mkSecurityGroupRule = {
    region,
    prefix,
    rule,
    protocol,
  }: let
    common = {
      provider = awsProviderFor region;
      inherit (rule) type;
      from_port = rule.from;
      to_port = rule.to;
      inherit protocol;
      security_group_id = rule.securityGroupId;
    };

    from-self =
      lib.nameValuePair "${prefix}-${rule.type}-${protocol}-${rule.name}-self"
      (common // {self = true;});

    from-cidr =
      lib.nameValuePair "${prefix}-${rule.type}-${protocol}-${rule.name}-cidr"
      (common // {cidr_blocks = lib.unique rule.cidrs;});

    from-ssgi =
      lib.nameValuePair "${prefix}-${rule.type}-${protocol}-${rule.name}-ssgi"
      (common // {source_security_group_id = rule.sourceSecurityGroupId;});
  in
    (lib.optional rule.self from-self)
    ++ (lib.optional (rule.cidrs != []) from-cidr)
    ++ (lib.optional (rule.sourceSecurityGroupId != null) from-ssgi);

  allowS3For = bucketArn: prefix: rootDir: bucketDirs: {
    "${prefix}-s3-bucket-console" = {
      effect = "Allow";
      actions = ["s3:ListAllMyBuckets" "s3:GetBucketLocation"];
      resources = ["arn:aws:s3:::*"];
    };

    "${prefix}-s3-bucket-listing" = {
      effect = "Allow";
      actions = ["s3:ListBucket"];
      resources = [bucketArn];
      condition = lib.forEach bucketDirs (dir: let
        # apply policy on all subdirs
        dir' = dir + "/*";
      in {
        test = "StringLike";
        variable = "s3:prefix";
        values = pathPrefix rootDir dir';
      });
    };

    "${prefix}-s3-directory-actions" = {
      effect = "Allow";
      actions = ["s3:*"];
      resources = lib.unique (lib.flatten (lib.forEach bucketDirs (dir: [
        # apply policy on all subdirs
        "${bucketArn}/${rootDir}/${dir}/*"
        "${bucketArn}/${rootDir}/${dir}"
      ])));
    };
  };

  allowS3ForTempo = bucketTempoArn: prefix: {
    # Requirements from:
    # https://grafana.com/docs/tempo/latest/configuration/s3/
    "${prefix}-s3-tempo-bucket" = {
      effect = "Allow";
      actions = [
        "s3:DeleteObject"
        "s3:GetObject"
        "s3:GetObjectTagging"
        "s3:ListBucket"
        "s3:PutObject"
        "s3:PutObjectTagging"
      ];
      resources = [
        "${bucketTempoArn}/*"
        "${bucketTempoArn}"
      ];
    };
  };

  mkStorage = host: kms: specs: {
    availability_zone = var "aws_instance.${host}.availability_zone";
    encrypted = true;
    inherit
      (specs)
      iops
      size
      type
      throughput
      ;
    kms_key_id = kms;
  };

  mkAttachment = host: volume: device_name: {
    inherit device_name;
    volume_id = var "aws_ebs_volume.${volume}.id";
    instance_id = var "aws_instance.${host}.id";
  };
}
