{ self, config, pkgs, lib, terralib, ... }:
let
  inherit (terralib)
    id var regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute nullRouteInline;
  inherit (config.cluster) vbkBackend vbkBackendSkipCertVerification;

  merge = lib.foldl' lib.recursiveUpdate { };

  tags = { Cluster = config.cluster.name; };

  mapAwsAsgVpcs = terralib.aws.mapAsgVpcs config.cluster;
  mapAwsAsgVpcsToList = terralib.aws.mapAsgVpcsToList config.cluster;
  # As long as we have 1 vpc per region for autoscaling groups,
  # the following approach should work for mesh vpc peering and routing
  # between them since we cannot route through a star vpc peered topology:
  # https://docs.aws.amazon.com/vpc/latest/peering/peering-configurations-full-access.html#one-to-many-vpcs-full-access
  mapAwsAsgVpcPeers = let
    # Generate a region sorted list with the assumption of only 1 vpc per region
    vpcRegions =
      lib.unique (lib.sort (a: b: a < b) (mapAwsAsgVpcsToList (vpc: vpc.region)));

    # The following definitions prepare a mesh of unique peeringPairs,
    # each with a connector and accepter.  The following is an example of
    # a vpcRegions input list and a peeringPairs output list:
    #
    # vpcRegions = [ "us-east-2" "eu-central-1" "eu-west-1" ]
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
    peeringPairs = lib.flatten
      (lib.imap0 (i: connector: regionPeeringPairs vpcRegions connector i)
        vpcRegions);
  in f: lib.listToAttrs (lib.forEach peeringPairs f);
in {
  tf.clients.configuration = {
    terraform.backend.http = let
      vbk =
        "${vbkBackend}/state/${config.cluster.name}/clients";
    in {
      address = vbk;
      lock_address = vbk;
      unlock_address = vbk;
      skip_cert_verification = vbkBackendSkipCertVerification;
    };

    terraform.required_providers = pkgs.terraform-provider-versions;

    provider.aws = [{ inherit (config.cluster) region; }]
      ++ (lib.forEach regions (region: {
        inherit region;
        alias = awsProviderNameFor region;
      }));

    # ---------------------------------------------------------------
    # Networking
    # ---------------------------------------------------------------

    resource.aws_vpc = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        lifecycle = [{ create_before_destroy = true; }];

        cidr_block = vpc.cidr;
        enable_dns_hostnames = true;
        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      });

    resource.aws_internet_gateway = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        lifecycle = [{ create_before_destroy = true; }];

        vpc_id = id "aws_vpc.${vpc.region}";
        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      });

    resource.aws_route_table = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        vpc_id = id "aws_vpc.${vpc.region}";

        route = [
          (nullRouteInline // {
            cidr_block = "0.0.0.0/0";
            gateway_id = id "aws_internet_gateway.${vpc.region}";
          })
          (nullRouteInline // {
            cidr_block = config.cluster.vpc.cidr;
            vpc_peering_connection_id =
              id "aws_vpc_peering_connection.${vpc.region}";
          })
        ] ++ (lib.forEach (lib.flip lib.filter (terralib.aws.asgVpcs config.cluster)
          (innerVpc: innerVpc.region != vpc.region)) (innerVpc:
            # Derive the proper peerPairing connection name using a comparison
            let
              connector = if innerVpc.region < vpc.region then
                innerVpc.region
              else
                vpc.region;
              accepter = if innerVpc.region > vpc.region then
                innerVpc.region
              else
                vpc.region;
            in nullRouteInline // {
              cidr_block = innerVpc.cidr;
              vpc_peering_connection_id = id
                "aws_vpc_peering_connection.${connector}-connect-${accepter}";
            }));

        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      });

    data.aws_route_table."${config.cluster.name}" = {
      provider = awsProviderFor config.cluster.region;
      filter = {
        name = "tag:Name";
        values = [ config.cluster.name ];
      };
    };

    resource.aws_route = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region (nullRoute // {
        route_table_id = id "data.aws_route_table.${config.cluster.name}";
        destination_cidr_block = vpc.cidr;
        vpc_peering_connection_id =
          id "aws_vpc_peering_connection.${vpc.region}";
      }));

    resource.aws_subnet = mapAwsAsgVpcs (vpc:
      lib.flip lib.mapAttrsToList vpc.subnets (suffix: subnet:
        lib.nameValuePair "${vpc.region}-${suffix}" {
          provider = awsProviderFor vpc.region;
          vpc_id = id "aws_vpc.${vpc.region}";
          cidr_block = subnet.cidr;

          lifecycle = [{ create_before_destroy = true; }];

          tags = tags // {
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
        values = [ config.cluster.vpc.name ];
      };
    };

    data.aws_caller_identity.core = {
      provider = awsProviderFor config.cluster.region;
    };

    # Set up vpc pairing from each autoscaling region to the core region (1st block)
    # Then add on the mesh vpc pairing connections (2nd block)
    resource.aws_vpc_peering_connection = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        vpc_id = id "aws_vpc.${vpc.region}";
        peer_vpc_id = id "data.aws_vpc.core";
        peer_owner_id = var "data.aws_caller_identity.core.account_id";
        peer_region = config.cluster.region;
        auto_accept = false;
        lifecycle = [{ create_before_destroy = true; }];

        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      }) // (mapAwsAsgVpcPeers (link:
        lib.nameValuePair "${link.connector}-connect-${link.accepter}" {
          provider = awsProviderFor link.connector;
          vpc_id = id "aws_vpc.${link.connector}";
          peer_vpc_id = id "aws_vpc.${link.accepter}";
          peer_owner_id = var "data.aws_caller_identity.core.account_id";
          peer_region = link.accepter;
          auto_accept = false;
          lifecycle = [{ create_before_destroy = true; }];

          tags = tags // {
            Name = "${link.connector}-connect-${link.accepter}";
            Region = link.connector;
          };
        }));

    # Accept vpc pairing from each autoscaling region to the core region (1st block)
    # Then accept the mesh vpc pairing connections (2nd block)
    resource.aws_vpc_peering_connection_accepter = mapAwsAsgVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor config.cluster.region;
        vpc_peering_connection_id =
          id "aws_vpc_peering_connection.${vpc.region}";
        auto_accept = true;
        lifecycle = [{ create_before_destroy = true; }];
        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      }) // (mapAwsAsgVpcPeers (link:
        lib.nameValuePair "${link.accepter}-accept-${link.connector}" {
          provider = awsProviderFor link.accepter;
          vpc_peering_connection_id = id
            "aws_vpc_peering_connection.${link.connector}-connect-${link.accepter}";
          auto_accept = true;
          lifecycle = [{ create_before_destroy = true; }];
          tags = tags // {
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

          accepter = { allow_remote_vpc_dns_resolution = true; };
        });

      requesterCorePeeringOptions = mapAwsAsgVpcs (vpc:
        lib.nameValuePair vpc.region {
          provider = awsProviderFor vpc.region;
          vpc_peering_connection_id =
            id "aws_vpc_peering_connection.${vpc.region}";

          requester = { allow_remote_vpc_dns_resolution = true; };
        });

      accepterMeshPeeringOptions = mapAwsAsgVpcPeers (link:
        lib.nameValuePair "${link.accepter}-accept-${link.connector}" {
          provider = awsProviderFor link.accepter;
          vpc_peering_connection_id = id
            "aws_vpc_peering_connection_accepter.${link.accepter}-accept-${link.connector}";

          accepter = { allow_remote_vpc_dns_resolution = true; };
        });

      requesterMeshPeeringOptions = mapAwsAsgVpcPeers (link:
        lib.nameValuePair "${link.connector}-connect-${link.accepter}" {
          provider = awsProviderFor link.connector;
          vpc_peering_connection_id = id
            "aws_vpc_peering_connection.${link.connector}-connect-${link.accepter}";

          requester = { allow_remote_vpc_dns_resolution = true; };
        });

      recursiveMerge = lib.foldr lib.recursiveUpdate { };
    in recursiveMerge [
      accepterCorePeeringOptions
      accepterMeshPeeringOptions
      requesterCorePeeringOptions
      requesterMeshPeeringOptions
    ];

    # ---------------------------------------------------------------
    # SSL/TLS - root ssh
    # ---------------------------------------------------------------

    resource.aws_key_pair = lib.mkIf config.cluster.generateSSHKey
      (lib.listToAttrs (let
        usedRegions = lib.unique
          ((lib.forEach (builtins.attrValues config.cluster.awsAutoScalingGroups)
            (group: group.region)) ++ [ config.cluster.region ]);
      in lib.forEach usedRegions (region:
        lib.nameValuePair region {
          provider = awsProviderFor region;
          key_name = "${config.cluster.name}-${region}";
          public_key = var ''file("secrets/ssh-${config.cluster.name}.pub")'';
        })));

    # ---------------------------------------------------------------
    # Instance IAM + Security Group
    # ---------------------------------------------------------------

    resource.aws_iam_instance_profile =
      lib.flip lib.mapAttrs' config.cluster.awsAutoScalingGroups (name: group:
        lib.nameValuePair group.uid {
          name = group.uid;
          inherit (group.iam.instanceProfile) path;
          role = group.iam.instanceProfile.role.tfName;
          lifecycle = [{ create_before_destroy = true; }];
        });

    data.aws_iam_policy_document = let
      # deploy for client role
      role = config.cluster.iam.roles.client;
      op = policyName: policy:
        lib.nameValuePair policy.uid {
          statement = {
            inherit (policy) effect actions resources;
          } // (lib.optionalAttrs (policy.condition != null) {
            inherit (policy) condition;
          });
        };
    in lib.listToAttrs (lib.mapAttrsToList op role.policies);

    resource.aws_iam_role = let
      # deploy for client role
      role = config.cluster.iam.roles.client;
    in {
      "${role.uid}" = {
        name = role.uid;
        assume_role_policy = role.assumePolicy.tfJson;
        lifecycle = [{ create_before_destroy = true; }];
      };
    };

    resource.aws_iam_role_policy = let
      # deploy for client role
      role = config.cluster.iam.roles.client;
      op = policyName: policy:
        lib.nameValuePair policy.uid {
          name = policy.uid;
          role = role.id;
          policy = var "data.aws_iam_policy_document.${policy.uid}.json";
        };
    in lib.listToAttrs (lib.mapAttrsToList op role.policies);

    resource.aws_security_group =
      lib.flip lib.mapAttrsToList config.cluster.awsAutoScalingGroups
      (name: group: {
        "${group.uid}" = {
          provider = awsProviderFor group.region;
          name_prefix = "${group.uid}-";
          description = "Security group for ASG in ${group.uid}";
          vpc_id = id "aws_vpc.${group.region}";
          lifecycle = [{ create_before_destroy = true; }];
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
    in merge awsAsgs;

    # ---------------------------------------------------------------
    # Auto Scaling Groups
    # ---------------------------------------------------------------

    resource.aws_autoscaling_group =
      lib.flip lib.mapAttrs' config.cluster.awsAutoScalingGroups (name: group:
        lib.nameValuePair group.uid {
          provider = awsProviderFor group.region;
          launch_configuration =
            var "aws_launch_configuration.${group.uid}.name";

          name = group.uid;

          vpc_zone_identifier = lib.flip lib.mapAttrsToList group.vpc.subnets
            (suffix: _: id "aws_subnet.${group.region}-${suffix}");

          min_size = group.minSize;
          max_size = group.maxSize;
          desired_capacity = group.desiredCapacity;

          health_check_type = "EC2";
          health_check_grace_period = 300;
          wait_for_capacity_timeout = "2m";
          termination_policies = [ "OldestLaunchTemplate" ];
          max_instance_lifetime = group.maxInstanceLifetime;

          lifecycle = [{ create_before_destroy = true; }];

          tag = let
            tags = {
              Cluster = config.cluster.name;
              Name = group.name;
              UID = group.uid;
              Consul = "client";
              Vault = "client";
              Nomad = "client";
            } // group.tags;
          in lib.mapAttrsToList (key: value: {
            inherit key value;
            propagate_at_launch = true;
          }) tags;
        });

    resource.aws_launch_configuration =
      lib.flip lib.mapAttrs' config.cluster.awsAutoScalingGroups (name: group:
        lib.nameValuePair group.uid (lib.mkMerge [
          {
            provider = awsProviderFor group.region;
            name_prefix = "${group.uid}-";
            image_id = group.ami;
            instance_type = group.instanceType;

            iam_instance_profile = group.iam.instanceProfile.tfName;

            security_groups = [ group.securityGroupId ];
            placement_tenancy = "default";
            # TODO: switch this to false for production
            associate_public_ip_address = group.associatePublicIP;

            ebs_optimized = false;

            lifecycle = [{ create_before_destroy = true; }];

            ebs_block_device = {
              device_name = "/dev/xvdb";
              volume_type = group.volumeType;
              volume_size = group.volumeSize;
              delete_on_termination = true;
            };
          }

          (lib.mkIf config.cluster.generateSSHKey {
            key_name = var "aws_key_pair.${group.region}.key_name";
          })

          (lib.mkIf (group.userData != null) { user_data = group.userData; })
        ]));
  };
}
