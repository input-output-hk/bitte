{
  self,
  config,
  pkgs,
  lib,
  terralib,
  ...
}: let
  inherit
    (terralib)
    id
    var
    regions
    awsProviderNameFor
    awsProviderFor
    mkSecurityGroupRule
    nullRoute
    nullRouteInline
    ;
  inherit (config.cluster) infraType vbkBackend vbkBackendSkipCertVerification;

  merge = lib.foldl' lib.recursiveUpdate {};

  tags = {Cluster = config.cluster.name;};

  # See lib defn for attr struct example.
  mapAwsAsgVpcs = terralib.aws.mapAsgVpcs config.cluster;
  mapAwsAsgVpcsToList = terralib.aws.mapAsgVpcsToList config.cluster;

  # Generate a region sorted list of asg vpcs with the assumption of only 1 vpc per region
  vpcAsgRegions =
    lib.unique (lib.sort (a: b: a < b) (mapAwsAsgVpcsToList (vpc: vpc.region)));

  # As long as we have 1 vpc per region for autoscaling groups,
  # the following approach should work for mesh vpc peering and routing
  # between them since we cannot route through a star vpc peered topology:
  # https://docs.aws.amazon.com/vpc/latest/peering/peering-configurations-full-access.html#one-to-many-vpcs-full-access
  mapAwsAsgVpcPeers = let
    # The following definitions prepare a mesh of unique peeringPairs,
    # each with a connector and accepter.  The following is an example of
    # a vpcAsgRegions input list and a peeringPairs output list:
    #
    # vpcAsgRegions = [ "us-east-2" "eu-central-1" "eu-west-1" ]
    # peeringPairs = [
    #   { connector = "eu-central-1"; accepter = "eu-west-1"; }
    #   { connector = "eu-central-1"; accepter = "us-east-2"; }
    #   { connector = "eu-west-1";    accepter = "us-east-2"; }
    # ]
    regionPeeringPairs = vpcs: connector: index:
      map (accepter: {
        inherit connector;
        inherit accepter;
      }) (lib.drop (index + 1) vpcs);
    peeringPairs =
      lib.flatten
      (lib.imap0 (i: connector: regionPeeringPairs vpcAsgRegions connector i)
        vpcAsgRegions);
  in
    f: lib.listToAttrs (lib.forEach peeringPairs f);

  # Generate a list of total regions between core and asg regions for transit gateway purposes
  vpcRegions =
    lib.unique (lib.sort (a: b: a < b) ([config.cluster.region] ++ (mapAwsAsgVpcsToList (vpc: vpc.region))));

  # Regions where the coreNodes don't reside, for transit gateway purposes
  transitGatewayPeerRegions = lib.filter (x: x != config.cluster.region) vpcRegions;

  cfgTg = config.cluster.transitGateway;
  isTg = cfgTg.enable == true;

  infraTypeCheck =
    if builtins.elem infraType ["aws" "premSim"]
    then true
    else
      (throw ''
        To utilize the clients TF attr, the cluster config parameter `infraType`
        must either "aws" or "premSim".
      '');
in {
  tf.clients.configuration = lib.mkIf infraTypeCheck {
    terraform.backend = lib.mkIf (vbkBackend != "local") {
      http = let
        vbk = "${vbkBackend}/state/${config.cluster.name}/clients";
      in {
        address = vbk;
        lock_address = vbk;
        unlock_address = vbk;
        skip_cert_verification = vbkBackendSkipCertVerification;
      };
    };

    terraform.required_providers = pkgs.terraform-provider-versions;

    provider.aws =
      [{inherit (config.cluster) region;}]
      ++ (lib.forEach regions (region: {
        inherit region;
        alias = awsProviderNameFor region;
      }));

    module = mapAwsAsgVpcs (vpc:
      lib.nameValuePair "instance_types_to_azs_${vpc.region}" {
        providers.aws = awsProviderFor vpc.region;
        source = "${./modules/instance-types-to-azs}";
        instance_types = config.cluster.requiredAsgInstanceTypes;
      });

    # ---------------------------------------------------------------
    # Networking
    # ---------------------------------------------------------------

    resource.aws_vpc = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        lifecycle = [{create_before_destroy = true;}];

        cidr_block = vpc.cidr;
        enable_dns_hostnames = true;
        tags =
          tags
          // {
            Name = vpc.name;
            Region = vpc.region;
          };
      });

    resource.aws_internet_gateway = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        lifecycle = [{create_before_destroy = true;}];

        vpc_id = id "aws_vpc.${vpc.region}";
        tags =
          tags
          // {
            Name = vpc.name;
            Region = vpc.region;
          };
      });

    resource.aws_route_table = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        vpc_id = id "aws_vpc.${vpc.region}";

        route =
          [
            (nullRouteInline
              // {
                cidr_block = "0.0.0.0/0";
                gateway_id = id "aws_internet_gateway.${vpc.region}";
              })
            (nullRouteInline
              // {
                cidr_block = config.cluster.vpc.cidr;
                vpc_peering_connection_id =
                  id "aws_vpc_peering_connection.${vpc.region}";
              })
          ]
          ++ (lib.forEach (lib.flip lib.filter (terralib.aws.asgVpcs config.cluster)
            (innerVpc: innerVpc.region != vpc.region)) (innerVpc:
            # Derive the proper peerPairing connection name using a comparison
            let
              connector =
                if innerVpc.region < vpc.region
                then innerVpc.region
                else vpc.region;
              accepter =
                if innerVpc.region > vpc.region
                then innerVpc.region
                else vpc.region;
            in
              nullRouteInline
              // {
                cidr_block = innerVpc.cidr;
                vpc_peering_connection_id =
                  id
                  "aws_vpc_peering_connection.${connector}-connect-${accepter}";
              }))
          ++ lib.optionals isTg (
            map
            (transitRoute:
              nullRouteInline
              // {
                cidr_block = transitRoute.cidrRange;
                transit_gateway_id = id "aws_ec2_transit_gateway.${vpc.region}";
              })
            cfgTg.transitRoutes
          );

        tags =
          tags
          // {
            Name = vpc.name;
            Region = vpc.region;
          };
      });

    data.aws_route_table."${config.cluster.name}" = {
      provider = awsProviderFor config.cluster.region;
      filter = {
        name = "tag:Name";
        values = [config.cluster.name];
      };
    };

    data.aws_subnet =
      lib.mapAttrs (n: v: {
        provider = awsProviderFor config.cluster.region;
        filter = {
          name = "tag:Name";
          values = [v.name];
        };
      })
      config.cluster.vpc.subnets;

    resource.aws_route =
      mapAwsAsgVpcs (vpc:
        lib.nameValuePair vpc.region (nullRoute
          // {
            route_table_id = id "data.aws_route_table.${config.cluster.name}";
            destination_cidr_block = vpc.cidr;
            vpc_peering_connection_id =
              id "aws_vpc_peering_connection.${vpc.region}";
          }))
      // lib.optionalAttrs isTg (
        lib.listToAttrs (lib.imap1 (
            i: transitRoute:
              lib.nameValuePair "transit-gateway-route-${toString i}" (nullRoute
                // {
                  provider = awsProviderFor config.cluster.region;
                  route_table_id = id "data.aws_route_table.${config.cluster.name}";
                  destination_cidr_block = transitRoute.cidrRange;
                  network_interface_id = id "data.aws_network_interface.${transitRoute.gatewayCoreNodeName}";
                })
          )
          cfgTg.transitRoutes)
      );

    resource.aws_s3_bucket_object = lib.flip lib.mapAttrs' config.cluster.awsAutoScalingGroups (name: group:
      lib.nameValuePair "${name}-flake" rec {
        bucket = config.cluster.s3Bucket;
        key = with config; "infra/secrets/${cluster.name}/${cluster.kms}/source/${name}-source.tar.xz";
        etag = var ''filemd5("${source}")'';
        source = "${pkgs.runCommand "source.tar.xz" {} ''
          tar cvf $out -C ${config.cluster.flakePath} .
        ''}";
      });

    resource.aws_subnet = mapAwsAsgVpcs (vpc:
      lib.flip lib.mapAttrsToList vpc.subnets (suffix: subnet:
        lib.nameValuePair "${vpc.region}-${suffix}" {
          provider = awsProviderFor vpc.region;
          vpc_id = id "aws_vpc.${vpc.region}";
          cidr_block = subnet.cidr;
          availability_zone = subnet.availabilityZone;

          lifecycle = [{create_before_destroy = true;}];

          tags =
            tags
            // {
              Region = vpc.region;
              Name = "${vpc.region}-${suffix}";
            };
        }));

    resource.aws_route_table_association = mapAwsAsgVpcs (vpc:
      lib.flip lib.mapAttrsToList vpc.subnets (suffix: subnet:
        lib.nameValuePair "${vpc.region}-${suffix}" {
          provider = awsProviderFor vpc.region;
          subnet_id = id "aws_subnet.${vpc.region}-${suffix}";
          route_table_id = id "aws_route_table.${vpc.region}";
        }));

    data.aws_vpc.core = {
      provider = awsProviderFor config.cluster.region;
      filter = {
        name = "tag:Name";
        values = [config.cluster.vpc.name];
      };
    };

    data.aws_caller_identity.core = {
      provider = awsProviderFor config.cluster.region;
    };

    # Set up vpc pairing from each autoscaling region to the core region (1st block)
    # Then add on the mesh vpc pairing connections (2nd block)
    resource.aws_vpc_peering_connection =
      mapAwsAsgVpcs (vpc:
        lib.nameValuePair vpc.region {
          provider = awsProviderFor vpc.region;
          vpc_id = id "aws_vpc.${vpc.region}";
          peer_vpc_id = id "data.aws_vpc.core";
          peer_owner_id = var "data.aws_caller_identity.core.account_id";
          peer_region = config.cluster.region;
          auto_accept = false;
          lifecycle = [{create_before_destroy = true;}];

          tags =
            tags
            // {
              Name = vpc.name;
              Region = vpc.region;
            };
        })
      // (mapAwsAsgVpcPeers (link:
        lib.nameValuePair "${link.connector}-connect-${link.accepter}" {
          provider = awsProviderFor link.connector;
          vpc_id = id "aws_vpc.${link.connector}";
          peer_vpc_id = id "aws_vpc.${link.accepter}";
          peer_owner_id = var "data.aws_caller_identity.core.account_id";
          peer_region = link.accepter;
          auto_accept = false;
          lifecycle = [{create_before_destroy = true;}];

          tags =
            tags
            // {
              Name = "${link.connector}-connect-${link.accepter}";
              Region = link.connector;
            };
        }));

    # Accept vpc pairing from each autoscaling region to the core region (1st block)
    # Then accept the mesh vpc pairing connections (2nd block)
    resource.aws_vpc_peering_connection_accepter =
      mapAwsAsgVpcs (vpc:
        lib.nameValuePair vpc.region {
          provider = awsProviderFor config.cluster.region;
          vpc_peering_connection_id =
            id "aws_vpc_peering_connection.${vpc.region}";
          auto_accept = true;
          lifecycle = [{create_before_destroy = true;}];
          tags =
            tags
            // {
              Name = vpc.name;
              Region = vpc.region;
            };
        })
      // (mapAwsAsgVpcPeers (link:
        lib.nameValuePair "${link.accepter}-accept-${link.connector}" {
          provider = awsProviderFor link.accepter;
          vpc_peering_connection_id =
            id
            "aws_vpc_peering_connection.${link.connector}-connect-${link.accepter}";
          auto_accept = true;
          lifecycle = [{create_before_destroy = true;}];
          tags =
            tags
            // {
              Name = "${link.accepter}-accept-${link.connector}";
              Region = link.accepter;
            };
        }));

    # Set up cross vpc DNS resolution from each autoscaling region to the core region (1st and 2nd let block defns)
    # Then add on the mesh cross vpc DNS resolution (3rd and 4th let block defns)
    resource.aws_vpc_peering_connection_options = let
      accepterCorePeeringOptions = mapAwsAsgVpcs (vpc:
        lib.nameValuePair "${vpc.region}-accepter" {
          provider = awsProviderFor config.cluster.region;
          vpc_peering_connection_id =
            id "aws_vpc_peering_connection_accepter.${vpc.region}";

          accepter = {allow_remote_vpc_dns_resolution = true;};
        });

      requesterCorePeeringOptions = mapAwsAsgVpcs (vpc:
        lib.nameValuePair vpc.region {
          provider = awsProviderFor vpc.region;
          vpc_peering_connection_id =
            id "aws_vpc_peering_connection_accepter.${vpc.region}";

          requester = {allow_remote_vpc_dns_resolution = true;};
        });

      accepterMeshPeeringOptions = mapAwsAsgVpcPeers (link:
        lib.nameValuePair "${link.accepter}-accept-${link.connector}" {
          provider = awsProviderFor link.accepter;
          vpc_peering_connection_id =
            id
            "aws_vpc_peering_connection_accepter.${link.accepter}-accept-${link.connector}";

          accepter = {allow_remote_vpc_dns_resolution = true;};
        });

      requesterMeshPeeringOptions = mapAwsAsgVpcPeers (link:
        lib.nameValuePair "${link.connector}-connect-${link.accepter}" {
          provider = awsProviderFor link.connector;
          vpc_peering_connection_id =
            id
            "aws_vpc_peering_connection_accepter.${link.accepter}-accept-${link.connector}";

          requester = {allow_remote_vpc_dns_resolution = true;};
        });

      recursiveMerge = lib.foldr lib.recursiveUpdate {};
    in
      recursiveMerge [
        accepterCorePeeringOptions
        accepterMeshPeeringOptions
        requesterCorePeeringOptions
        requesterMeshPeeringOptions
      ];

    # ---------------------------------------------------------------
    # SSL/TLS - root ssh
    # ---------------------------------------------------------------

    resource.aws_key_pair =
      lib.mkIf config.cluster.generateSSHKey
      (lib.listToAttrs (let
        usedRegions =
          lib.unique
          ((lib.forEach (builtins.attrValues config.cluster.awsAutoScalingGroups)
            (group: group.region))
          ++ [config.cluster.region]);
      in
        lib.forEach usedRegions (region:
          lib.nameValuePair region {
            provider = awsProviderFor region;
            key_name = "${config.cluster.name}-${region}";
            public_key = var ''file("secrets/ssh-${config.cluster.name}.pub")'';
          })));

    # ---------------------------------------------------------------
    # Instance IAM + Security Group
    # ---------------------------------------------------------------

    resource.aws_iam_instance_profile = lib.flip lib.mapAttrs' config.cluster.awsAutoScalingGroups (name: group:
      lib.nameValuePair group.uid {
        name = group.uid;
        inherit (group.iam.instanceProfile) path;
        role = var "data.aws_iam_role.${config.cluster.iam.roles.client.uid}.name";
        lifecycle = [{create_before_destroy = true;}];
      });

    data.aws_iam_role = let
      # deploy for core role
      inherit (config.cluster.iam.roles.client) uid;
    in {
      "${uid}".name = "core-${uid}";
    };

    data.aws_iam_policy_document = let
      # deploy for client role
      role = config.cluster.iam.roles.client;
      op = policyName: policy:
        lib.nameValuePair policy.uid {
          statement =
            {
              inherit (policy) effect actions resources;
            }
            // (lib.optionalAttrs (policy.condition != null) {
              inherit (policy) condition;
            });
        };
    in
      lib.mapAttrs' op role.policies;

    resource.aws_iam_role_policy = let
      # deploy for client role
      role = config.cluster.iam.roles.client;
      op = policyName: policy:
        lib.nameValuePair policy.uid {
          name = policy.uid;
          role = id "data.aws_iam_role.${role.uid}";
          policy = var "data.aws_iam_policy_document.${policy.uid}.json";
        };
    in
      lib.mapAttrs' op role.policies;

    resource.aws_security_group =
      lib.flip lib.mapAttrsToList config.cluster.awsAutoScalingGroups
      (name: group: {
        "${group.uid}" = {
          provider = awsProviderFor group.region;
          name_prefix = "${group.uid}-";
          description = "Security group for ASG in ${group.uid}";
          vpc_id = id "aws_vpc.${group.region}";
          lifecycle = [{create_before_destroy = true;}];
        };
      });

    resource.aws_security_group_rule = let
      mapAwsAsg' = _: group:
        merge (lib.flip lib.mapAttrsToList group.securityGroupRules (_: rule:
          lib.listToAttrs (lib.flatten (lib.flip map rule.protocols (protocol:
            mkSecurityGroupRule {
              prefix = group.uid;
              inherit (group) region;
              inherit rule protocol;
            })))));

      awsAsgs = lib.mapAttrsToList mapAwsAsg' config.cluster.awsAutoScalingGroups;
    in
      merge awsAsgs;

    # ---------------------------------------------------------------
    # Auto Scaling Groups
    # ---------------------------------------------------------------

    resource.aws_autoscaling_group = lib.flip lib.mapAttrs' config.cluster.awsAutoScalingGroups (name: group:
      lib.nameValuePair group.uid {
        provider = awsProviderFor group.region;
        launch_configuration =
          var "aws_launch_configuration.${group.uid}.name";

        name = group.uid;

        vpc_zone_identifier =
          lib.flip lib.mapAttrsToList group.vpc.subnets
          (suffix: _: id "aws_subnet.${group.region}-${suffix}");

        min_size = group.minSize;
        max_size = group.maxSize;
        desired_capacity = group.desiredCapacity;

        health_check_type = "EC2";
        health_check_grace_period = 300;
        wait_for_capacity_timeout = "2m";
        termination_policies = ["OldestLaunchTemplate"];
        max_instance_lifetime = group.maxInstanceLifetime;

        lifecycle = [{create_before_destroy = true;}];

        tag = let
          tags =
            {
              Cluster = config.cluster.name;
              Name = group.name;
              UID = group.uid;
              Consul = "client";
              Vault = "client";
              Nomad = "client";
            }
            // group.tags;
        in
          lib.mapAttrsToList (key: value: {
            inherit key value;
            propagate_at_launch = true;
          })
          tags;
      });

    resource.aws_launch_configuration = lib.flip lib.mapAttrs' config.cluster.awsAutoScalingGroups (name: group:
      lib.nameValuePair group.uid (lib.mkMerge [
        {
          provider = awsProviderFor group.region;
          name_prefix = "${group.uid}-";
          image_id = group.ami;
          instance_type = group.instanceType;

          iam_instance_profile = group.iam.instanceProfile.tfName;

          security_groups = [group.securityGroupId];
          placement_tenancy = "default";
          # TODO: switch this to false for production
          associate_public_ip_address = group.associatePublicIP;

          ebs_optimized = false;

          lifecycle = [{create_before_destroy = true;}];

          ebs_block_device = {
            device_name = "/dev/xvdb";
            volume_type = group.volumeType;
            volume_size = group.volumeSize;
            delete_on_termination = true;
          };

          # Metadata hop limit=2 required for containers on ec2 to have access to IMDSv2 tokens
          # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
          metadata_options = {
            http_endpoint = "enabled";
            http_put_response_hop_limit = 2;
            http_tokens = "optional";
          };
        }

        (lib.mkIf config.cluster.generateSSHKey {
          key_name = var "aws_key_pair.${group.region}.key_name";
        })

        (lib.mkIf (group.userData != null) {user_data = group.userData;})
      ]));

    # ---------------------------------------------------------------
    # Optional Transit Gateway and Routing
    # (see also resource.{aws_route_table,aws_route} above
    # ---------------------------------------------------------------

    data.aws_network_interface = lib.mkIf isTg (lib.listToAttrs (map (transitRoute:
      lib.nameValuePair transitRoute.gatewayCoreNodeName {
        provider = awsProviderFor config.cluster.region;
        filter = {
          name = "tag:Name";
          values = [transitRoute.gatewayCoreNodeName];
        };
      })
    cfgTg.transitRoutes));

    data.aws_ec2_transit_gateway_route_table = lib.mkIf isTg (lib.listToAttrs (lib.forEach vpcRegions (region:
      lib.nameValuePair region {
        provider = awsProviderFor region;
        filter = {
          name = "default-association-route-table";
          values = ["true"];
        };
        depends_on = ["aws_ec2_transit_gateway.${region}"];
      })));

    resource.aws_ec2_transit_gateway = lib.mkIf isTg (lib.listToAttrs (lib.forEach vpcRegions (region:
      lib.nameValuePair region {
        provider = awsProviderFor region;
        auto_accept_shared_attachments = "disable";
        default_route_table_association = "enable";
        default_route_table_propagation = "enable";
        dns_support = "enable";
        tags =
          tags
          // {
            Name = region;
            Region = region;
          };
        lifecycle = [{create_before_destroy = true;}];
      })));

    resource.aws_ec2_transit_gateway_vpc_attachment = let
      mkTransitGatewayVpcAttachment = region: vpc: type:
        lib.nameValuePair "${region}-${type}-vpc" {
          provider = awsProviderFor region;
          transit_gateway_id = id "aws_ec2_transit_gateway.${region}";

          vpc_id =
            if type == "asg"
            then id "aws_vpc.${vpc.region}"
            else id "data.aws_vpc.core";

          subnet_ids =
            if type == "asg"
            then lib.mapAttrsToList (_: v: id "aws_subnet.${region}-${v.name}") vpc.subnets
            else lib.mapAttrsToList (_: v: id "data.aws_subnet.${v.name}") vpc.subnets;

          dns_support = "enable";
          transit_gateway_default_route_table_association = "true";
          transit_gateway_default_route_table_propagation = "true";
          tags =
            tags
            // {
              Name = "${region}-${type}-vpc";
              Region = region;
            };
        };

      asgTransitGatewayVpcAttachments =
        mapAwsAsgVpcs (vpc:
          mkTransitGatewayVpcAttachment vpc.region vpc "asg");

      coreTransitGatewayVpcAttachments =
        lib.listToAttrs [(mkTransitGatewayVpcAttachment config.cluster.region config.cluster.vpc "core")];

      recursiveMerge = lib.foldr lib.recursiveUpdate {};
    in
      lib.mkIf isTg (recursiveMerge [
        asgTransitGatewayVpcAttachments
        coreTransitGatewayVpcAttachments
      ]);

    resource.aws_ec2_transit_gateway_route = let
      mkTransitGatewayRoute = region: transitRoute: i:
        lib.nameValuePair "${region}-static-${toString i}" {
          provider = awsProviderFor region;
          destination_cidr_block = transitRoute.cidrRange;
          transit_gateway_attachment_id =
            if region == config.cluster.region
            then (id "aws_ec2_transit_gateway_vpc_attachment.${region}-core-vpc")
            else (id "aws_ec2_transit_gateway_peering_attachment.${config.cluster.region}-connect-${region}");

          transit_gateway_route_table_id = id "data.aws_ec2_transit_gateway_route_table.${region}";
          blackhole = false;

          depends_on =
            if region == config.cluster.region
            then ["aws_ec2_transit_gateway_vpc_attachment.${region}-core-vpc"]
            else ["aws_ec2_transit_gateway_peering_attachment.${config.cluster.region}-connect-${region}"];
        };
    in
      lib.mkIf isTg (lib.listToAttrs (lib.flatten (
        lib.forEach vpcRegions (region:
          lib.imap1 (i: transitRoute: mkTransitGatewayRoute region transitRoute i) cfgTg.transitRoutes)
      )));

    # Set up a star topology peering with the core region
    resource.aws_ec2_transit_gateway_peering_attachment = lib.mkIf (builtins.length vpcRegions > 1 && isTg) (lib.listToAttrs (lib.forEach transitGatewayPeerRegions (
      peerRegion:
        lib.nameValuePair "${config.cluster.region}-connect-${peerRegion}" {
          provider = awsProviderFor config.cluster.region;
          peer_region = peerRegion;
          peer_transit_gateway_id = id "aws_ec2_transit_gateway.${peerRegion}";
          transit_gateway_id = id "aws_ec2_transit_gateway.${config.cluster.region}";
          tags =
            tags
            // {
              Name = "${config.cluster.region}-connect-${peerRegion}";
            };
        }
    )));

    resource.aws_ec2_transit_gateway_peering_attachment_accepter = lib.mkIf (builtins.length vpcRegions > 1 && isTg) (lib.listToAttrs (lib.forEach transitGatewayPeerRegions (
      peerRegion:
        lib.nameValuePair "${peerRegion}-accept-${config.cluster.region}" {
          provider = awsProviderFor peerRegion;
          transit_gateway_attachment_id = id "aws_ec2_transit_gateway_peering_attachment.${config.cluster.region}-connect-${peerRegion}";
          tags =
            tags
            // {
              Name = "${peerRegion}-accept-${config.cluster.region}";
            };
        }
    )));
  };
}
