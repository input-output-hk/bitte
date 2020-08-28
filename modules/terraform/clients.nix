{ self, config, pkgs, lib, ... }:
let
  inherit (pkgs.terralib)
    id var regions awsProviderNameFor awsProviderFor merge mkSecurityGroupRule;
  vpcs = pkgs.terralib.vpcs config.cluster;
in {
  tf.clients.configuration = {
    terraform.backend.remote = {
      organization = "iohk-midnight";
      workspaces = [{ prefix = "${config.cluster.name}_"; }];
    };

    output.cluster = {
      value = {
        flake = toString config.cluster.flakePath;
        kms = config.cluster.kms;
        name = config.cluster.name;
        nix = pkgs.nixFlakes;
        region = config.cluster.region;
        s3-bucket = config.cluster.s3Bucket;
        s3-cache = config.cluster.s3Cache;

        roles = lib.flip lib.mapAttrs config.cluster.iam.roles
          (name: role: { arn = var "data.aws_iam_role.${role.uid}.arn"; });

        instances = lib.flip lib.mapAttrs config.cluster.instances
          (name: server: {
            flake-attr =
              "nixosConfigurations.${server.uid}.config.system.build.toplevel";
            instance-type =
              var "data.aws_instance.${server.name}.instance_type";
            name = server.name;
            private-ip = var "data.aws_instance.${server.name}.private_ip";
            public-ip = var "data.aws_instance.${server.name}.public_ip";
            tags = server.tags;
            uid = server.uid;
          });

        asgs = lib.flip lib.mapAttrs config.cluster.autoscalingGroups
          (name: group: {
            flake-attr =
              "nixosConfigurations.${group.uid}.config.system.build.toplevel";
            instance-type =
              var "aws_launch_configuration.${group.uid}.instance_type";
            uid = group.uid;
            arn = var "aws_autoscaling_group.${group.uid}.arn";
            region = group.region;
            count = group.desiredCapacity;
          });
      };
    };

    data.aws_instance = lib.flip lib.mapAttrs config.cluster.instances
      (name: server: {
        filter = [{
          name = "tag:UID";
          values = [ server.uid ];
        }];
      });

    provider.aws = [{ region = config.cluster.region; }] ++ (lib.forEach regions
      (region: {
        inherit region;
        alias = awsProviderNameFor region;
      }));

    resource.aws_autoscaling_group =
      lib.flip lib.mapAttrs' config.cluster.autoscalingGroups (name: group:
        lib.nameValuePair group.uid {
          provider = awsProviderFor group.region;
          launch_configuration =
            var "aws_launch_configuration.${group.uid}.name";

          name = group.uid;

          vpc_zone_identifier =
            lib.flip lib.mapAttrsToList vpcs.${group.region}.subnets
            (suffix: _: id "data.aws_subnet.${group.region}-${suffix}");

          availability_zones = lib.flip lib.imap0 group.subnets (idx: _:
            var
            "data.aws_availability_zones.available_in_${group.region}.names[${
              toString idx
            }]");

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
      lib.flip lib.mapAttrs' config.cluster.autoscalingGroups (name: group:
        lib.nameValuePair group.uid (lib.mkMerge [
          {
            provider = awsProviderFor group.region;
            name = group.uid;
            image_id = group.ami;
            instance_type = group.instanceType;

            iam_instance_profile = group.iam.instanceProfile.tfName;

            security_groups = [ group.securityGroupId ];
            placement_tenancy = "default";
            # TODO: switch this to false for production
            associate_public_ip_address = group.associatePublicIP;

            ebs_optimized = false;

            lifecycle = [{ create_before_destroy = true; }];

            root_block_device = {
              volume_type = "gp2";
              volume_size = 100;
              delete_on_termination = true;
            };
          }

          (lib.mkIf config.cluster.generateSSHKey {
            key_name = var "aws_key_pair.${group.region}.key_name";
          })

          (lib.mkIf (group.userData != null) { user_data = group.userData; })
        ]));

    resource.aws_iam_instance_profile =
      lib.flip lib.mapAttrs' config.cluster.autoscalingGroups (name: group:
        lib.nameValuePair group.uid {
          name = group.uid;
          path = group.iam.instanceProfile.path;
          role = group.iam.instanceProfile.role.tfDataName;
          lifecycle = [{ create_before_destroy = true; }];
        });

    data.aws_iam_role = lib.flip lib.mapAttrs' config.cluster.iam.roles
      (roleName: role: lib.nameValuePair role.uid { name = role.uid; });

    resource.aws_key_pair = lib.mkIf (config.cluster.generateSSHKey)
      (lib.listToAttrs ((let
        usedRegions = lib.unique
          ((lib.forEach (builtins.attrValues config.cluster.autoscalingGroups)
            (group: group.region)) ++ [ config.cluster.region ]);
      in lib.forEach usedRegions (region:
        lib.nameValuePair region {
          provider = awsProviderFor region;
          key_name = "${config.cluster.name}-${region}";
          public_key = var ''file("secrets/ssh-${config.cluster.name}.pub")'';
        }))));

    resource.aws_security_group =
      lib.flip lib.mapAttrsToList config.cluster.autoscalingGroups
      (name: group: {
        "${group.uid}" = {
          provider = awsProviderFor group.region;
          name_prefix = "${group.uid}-";
          description = "Security group for ASG in ${group.uid}";
          vpc_id = id "data.aws_vpc.${group.region}";
          lifecycle = [{ create_before_destroy = true; }];
        };
      });

    data.aws_vpc = lib.flip lib.mapAttrs' vpcs (region: vpc:
      lib.nameValuePair region {
        inherit (vpc) provider;
        filter = {
          name = "tag:Name";
          values = [ vpc.name ];
        };
      });

    data.aws_subnet = lib.listToAttrs (lib.flatten
      (lib.flip lib.mapAttrsToList vpcs (region: vpc:
        lib.flip lib.mapAttrsToList vpc.subnets (suffix: cidr:
          lib.nameValuePair "${region}-${suffix}" {
            inherit (vpc) provider;
            tags = {
              Cluster = config.cluster.name;
              Name = "${region}-${suffix}";
            };
          }))));

    resource.aws_security_group_rule = let
      mapASG = _: group:
        merge (lib.flip lib.mapAttrsToList group.securityGroupRules (_: rule:
          lib.listToAttrs (lib.flatten (lib.flip map rule.protocols (protocol:
            mkSecurityGroupRule {
              prefix = group.uid;
              inherit (group) region;
              inherit rule protocol;
            })))));

      asgs = lib.mapAttrsToList mapASG config.cluster.autoscalingGroups;
    in merge asgs;

    data.aws_availability_zones = lib.listToAttrs (lib.flatten
      (lib.flip lib.mapAttrsToList config.cluster.autoscalingGroups (_: group:
        lib.nameValuePair "available_in_${group.region}" {
          provider = awsProviderFor group.region;
          state = "available";
        })));

    data.aws_caller_identity.core = {
      provider = awsProviderFor config.cluster.region;
    };
  };
}
