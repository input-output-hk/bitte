{ self, config, pkgs, lib, ... }:
let
  inherit (pkgs.terralib)
    id var regions awsProviderNameFor awsProviderFor merge mkSecurityGroupRule;

  mapVpcs = pkgs.terralib.mapVpcs config.cluster;
in {
  tf.clients.configuration = {
    terraform.backend.http = let
      vbk =
        "https://vbk.infra.aws.iohkdev.io/state/${config.cluster.name}/clients";
    in {
      address = vbk;
      lock_address = vbk;
      unlock_address = vbk;
    };

    terraform.required_providers = pkgs.terraform-provider-versions;

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

          vpc_zone_identifier = lib.flip lib.mapAttrsToList group.vpc.subnets
            (suffix: _: id "data.aws_subnet.${group.region}-${suffix}");

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

    data.aws_vpc = mapVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        filter = {
          name = "tag:Name";
          values = [ vpc.name ];
        };
      });

    data.aws_subnet = mapVpcs (vpc:
      lib.flip lib.mapAttrsToList vpc.subnets (suffix: cidr:
        lib.nameValuePair "${vpc.region}-${suffix}" {
          provider = awsProviderFor vpc.region;
          tags = {
            Cluster = config.cluster.name;
            Name = "${vpc.region}-${suffix}";
          };
        }));

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
