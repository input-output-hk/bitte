{ self, config, pkgs, lib, ... }:
let
  inherit (pkgs.terralib)
    id var regions awsProviderNameFor awsProviderFor merge mkSecurityGroupRule
    nullRoute;

  mapVpcs = pkgs.terralib.mapVpcs config.cluster;

  tags = { Cluster = config.cluster.name; };
in {
  tf.network.configuration = {
    terraform.backend.remote = {
      organization = config.cluster.terraformOrganization;
      workspaces = [{ prefix = "${config.cluster.name}_"; }];
    };

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
              nullRoute // {
                cidr_block = innerVpc.cidr;
                vpc_peering_connection_id =
                  id "aws_vpc_peering_connection.${vpc.region}";
              }));

        tags = tags // {
          Name = vpc.name;
          Region = vpc.region;
        };
      });

    # resource.aws_vpc_peering_connection =
    #   lib.pipe (pkgs.terralib.vpcs config.cluster) [
    #     (lib.filter (vpc: vpc.region != config.cluster.region))
    #     (map (vpc:
    #       lib.nameValuePair "${vpc.region}-requester" {
    #         provider = awsProviderFor vpc.region;
    #         vpc_id = id "aws_vpc.${vpc.region}";
    #         peer_vpc_id = id "aws_vpc.core";
    #         peer_owner_id = var "data.aws_caller_identity.core.account_id";
    #         peer_region = config.cluster.region;
    #         auto_accept = false;
    #         lifecycle = [{ create_before_destroy = true; }];
    #
    #         tags = tags // {
    #           Name = "${vpc.name}-requester";
    #           Region = vpc.region;
    #           Side = "requester";
    #         };
    #       }))
    #     builtins.listToAttrs
    #   ];

    # resource.aws_vpc_peering_connection_accepter =
    #   lib.pipe (pkgs.terralib.vpcs config.cluster) [
    #     (lib.filter (vpc: vpc.region != config.cluster.region))
    #     (map (vpc:
    #       lib.nameValuePair "${vpc.region}-accepter" {
    #         provider = awsProviderFor config.cluster.region;
    #         vpc_id = id "aws_vpc.core";
    #         peer_vpc_id = id "aws_vpc.${vpc.region}";
    #         vpc_peering_connection_id =
    #           id "aws_vpc_peering_connection.${vpc.region}-requester";
    #         auto_accept = true;
    #         lifecycle = [{ create_before_destroy = true; }];
    #         tags = tags // {
    #           Name = "${vpc.name}-accepter";
    #           Region = vpc.region;
    #           Side = "accepter";
    #         };
    #       }))
    #     builtins.listToAttrs
    #   ];

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
      });

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
      });
  };
}
