{ self, config, pkgs, lib, ... }:
let
  inherit (pkgs.terralib)
    id var regions awsProviderNameFor awsProviderFor merge mkSecurityGroupRule
    nullRoute;
  vpcs = pkgs.terralib.vpcs config.cluster;

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

    resource.aws_vpc = (lib.flip lib.mapAttrs' vpcs (region: vpc:
      lib.nameValuePair region {
        inherit (vpc) provider cidr_block;
        enable_dns_hostnames = true;
        lifecycle = [{ create_before_destroy = true; }];
        tags = tags // {
          Name = vpc.name;
          Region = region;
        };
      })) // {
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

    resource.aws_internet_gateway = lib.flip lib.mapAttrs' vpcs (region: vpc:
      lib.nameValuePair region {
        inherit (vpc) provider vpc_id;
        lifecycle = [{ create_before_destroy = true; }];
        tags = tags // {
          Name = vpc.name;
          Region = region;
        };
      });

    resource.aws_route_table = lib.flip lib.mapAttrs' vpcs (region: vpc:
      lib.nameValuePair region {
        inherit (vpc) provider vpc_id;

        route = [
          (nullRoute // {
            cidr_block = "0.0.0.0/0";
            gateway_id = id "aws_internet_gateway.${region}";
          })
          (nullRoute // {
            cidr_block = config.cluster.vpc.cidr;
            vpc_peering_connection_id =
              id "aws_vpc_peering_connection.${region}-requester";
          })
        ] ++ (lib.flip lib.mapAttrsToList (lib.flip lib.filterAttrs vpcs
          (innerRegion: vpc: innerRegion != region)) (innerRegion: vpc:
            nullRoute // {
              inherit (vpc) cidr_block;
              vpc_peering_connection_id =
                id "aws_vpc_peering_connection.${region}-requester";
            }));

        tags = tags // {
          Name = vpc.name;
          Region = region;
        };
      });

    resource.aws_vpc_peering_connection = lib.flip lib.mapAttrs' vpcs
      (region: vpc:
        lib.nameValuePair "${region}-requester" {
          inherit (vpc) provider vpc_id;
          peer_vpc_id = id "aws_vpc.core";
          peer_owner_id = var "data.aws_caller_identity.core.account_id";
          peer_region = config.cluster.region;
          auto_accept = false;
          lifecycle = [{ create_before_destroy = true; }];

          tags = tags // {
            Name = vpc.name;
            Region = region;
            Side = "requester";
          };
        });

    resource.aws_vpc_peering_connection_accepter = lib.flip lib.mapAttrs' vpcs
      (region: vpc:
        lib.nameValuePair "${region}-accepter" {
          provider = awsProviderFor config.cluster.region;
          vpc_peering_connection_id =
            id "aws_vpc_peering_connection.${region}-requester";
          auto_accept = true;
          lifecycle = [{ create_before_destroy = true; }];

          tags = tags // {
            Name = vpc.name;
            Region = region;
            Side = "accepter";
          };
        });

    resource.aws_subnet = lib.listToAttrs (lib.flatten
      (lib.flip lib.mapAttrsToList vpcs (region: vpc:
        lib.flip lib.mapAttrsToList vpc.subnets (suffix: cidr:
          lib.nameValuePair "${region}-${suffix}" {
            inherit (vpc) provider vpc_id;
            cidr_block = cidr;

            lifecycle = [{ create_before_destroy = true; }];

            tags = tags // {
              Region = region;
              Name = "${region}-${suffix}";
            };
          }))));

    resource.aws_route_table_association = lib.listToAttrs (lib.flatten
      (lib.flip lib.mapAttrsToList vpcs (region: vpc:
        lib.flip lib.mapAttrsToList vpc.subnets (suffix: cidr:
          lib.nameValuePair "${region}-${suffix}" {
            inherit (vpc) provider;
            subnet_id = id "aws_subnet.${region}-${suffix}";
            route_table_id = id "aws_route_table.${region}";
          }))));
  };
}
