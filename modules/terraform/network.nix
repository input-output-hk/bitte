{ self, config, pkgs, lib, ... }:
let
  inherit (pkgs.terralib)
    id var regions awsProviderNameFor awsProviderFor merge mkSecurityGroupRule
    nullRoute;

  mapVpcs = pkgs.terralib.mapVpcs config.cluster;
  mapVpcsToList = pkgs.terralib.mapVpcsToList config.cluster;

  # As long as we have 1 vpc per region for autoscaling groups,
  # the following approach should work for mesh vpc peering and routing
  # between them since we cannot route through a star vpc peered topology:
  # https://docs.aws.amazon.com/vpc/latest/peering/peering-configurations-full-access.html#one-to-many-vpcs-full-access

  # Generate a region sorted list with the assumption of only 1 vpc per region
  vpcRegions = lib.sort (a: b: a < b) (mapVpcsToList (vpc: vpc.region));

  # The following definitions prepare a mesh of unique peeringPairs,
  # each with a connector and acceptor.  The following is an example of
  # a vpcRegions input list and a peeringPairs output list:
  #
  # vpcRegions = [ "us-east-2" "eu-central-1" "eu-west-1" ]
  # peeringPairs = [
  #   { connector = "eu-central-1"; acceptor = "eu-west-1"; }
  #   { connector = "eu-central-1"; acceptor = "us-east-2"; }
  #   { connector = "eu-west-1";    acceptor = "us-east-2"; }
  # ]

  regionPeeringPairs = vpcs: connector: index:
    map (acceptor: {
      connector = connector;
      acceptor = acceptor;
    }) (lib.drop (index + 1) vpcs);
  peeringPairs = lib.flatten
    (lib.imap0 (i: connector: regionPeeringPairs vpcRegions connector i)
      vpcRegions);
  mapVpcPeers = f: lib.listToAttrs (lib.forEach peeringPairs f);

  tags = { Cluster = config.cluster.name; };
in stateMigration config.cluster "network" {
  tf.network.configuration = {
    terraform.backend.http = let
      vbk = "https://vbk.infra.aws.iohkdev.io/state/${config.cluster.name}/network";
    in {
      address = vbk;
      lock_address = vbk;
      unlock_address = vbk;
    };

    terraform.required_providers = pkgs.terraform-provider-versions;

    provider.aws = [{ region = config.cluster.region; }] ++ (lib.forEach regions
      (region: {
        inherit region;
        alias = awsProviderNameFor region;
      }));

    data.aws_caller_identity.core = {
      provider = awsProviderFor config.cluster.region;
    };

    resource.aws_vpc = mapVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        cidr_block = vpc.cidr;
        enable_dns_hostnames = true;
        lifecycle = [{ create_before_destroy = true; }];
        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      }) // {
        core = {
          provider = awsProviderFor config.cluster.region;
          cidr_block = config.cluster.vpc.cidr;
          enable_dns_hostnames = true;
          tags = {
            Cluster = config.cluster.name;
            Name = config.cluster.vpc.name;
            Region = config.cluster.region;
          };
        };
      };

    resource.aws_internet_gateway = mapVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        vpc_id = id "aws_vpc.${vpc.region}";
        lifecycle = [{ create_before_destroy = true; }];
        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      });

    resource.aws_route_table = mapVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        vpc_id = id "aws_vpc.${vpc.region}";

        route = [
          (nullRoute // {
            cidr_block = "0.0.0.0/0";
            gateway_id = id "aws_internet_gateway.${vpc.region}";
          })
          (nullRoute // {
            cidr_block = config.cluster.vpc.cidr;
            vpc_peering_connection_id =
              id "aws_vpc_peering_connection.${vpc.region}";
          })
        ] ++ (lib.forEach
          (lib.flip lib.filter (pkgs.terralib.vpcs config.cluster)
            (innerVpc: innerVpc.region != vpc.region)) (innerVpc:
              # Derive the proper peerPairing connection name using a comparison
              let
                connector = if innerVpc.region < vpc.region then
                  innerVpc.region
                else
                  vpc.region;
                acceptor = if innerVpc.region > vpc.region then
                  innerVpc.region
                else
                  vpc.region;
              in nullRoute // {
                cidr_block = innerVpc.cidr;
                vpc_peering_connection_id = id
                  "aws_vpc_peering_connection.${connector}-connect-${acceptor}";
              }));

        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      });

    resource.aws_subnet = mapVpcs (vpc:
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

    resource.aws_route_table_association = mapVpcs (vpc:
      lib.flip lib.mapAttrsToList vpc.subnets (suffix: subnet:
        lib.nameValuePair "${vpc.region}-${suffix}" {
          provider = awsProviderFor vpc.region;
          subnet_id = id "aws_subnet.${vpc.region}-${suffix}";
          route_table_id = id "aws_route_table.${vpc.region}";
        }));

    # Set up vpc pairing from each autoscaling region to the core region (1st block)
    # Then add on the mesh vpc pairing connections (2nd block)
    resource.aws_vpc_peering_connection = mapVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        vpc_id = id "aws_vpc.${vpc.region}";
        peer_vpc_id = id "aws_vpc.core";
        peer_owner_id = var "data.aws_caller_identity.core.account_id";
        peer_region = config.cluster.region;
        auto_accept = false;
        lifecycle = [{ create_before_destroy = true; }];

        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      }) // (mapVpcPeers (link:
        lib.nameValuePair "${link.connector}-connect-${link.acceptor}" {
          provider = awsProviderFor link.connector;
          vpc_id = id "aws_vpc.${link.connector}";
          peer_vpc_id = id "aws_vpc.${link.acceptor}";
          peer_owner_id = var "data.aws_caller_identity.core.account_id";
          peer_region = link.acceptor;
          auto_accept = false;
          lifecycle = [{ create_before_destroy = true; }];

          tags = tags // {
            Name = "${link.connector}-connect-${link.acceptor}";
            Region = link.connector;
          };
        }));

    # Accept vpc pairing from each autoscaling region to the core region (1st block)
    # Then accept the mesh vpc pairing connections (2nd block)
    resource.aws_vpc_peering_connection_accepter = mapVpcs (vpc:
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
      }) // (mapVpcPeers (link:
        lib.nameValuePair "${link.acceptor}-accept-${link.connector}" {
          provider = awsProviderFor link.acceptor;
          vpc_peering_connection_id = id
            "aws_vpc_peering_connection.${link.connector}-connect-${link.acceptor}";
          auto_accept = true;
          lifecycle = [{ create_before_destroy = true; }];
          tags = tags // {
            Name = "${link.acceptor}-accept-${link.connector}";
            Region = link.acceptor;
          };
        }));
  };
}
