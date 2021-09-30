{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute;

  mapVpcs = pkgs.terralib.mapVpcs config.cluster;
  mapVpcsToList = pkgs.terralib.mapVpcsToList config.cluster;

  merge = lib.foldl' lib.recursiveUpdate { };
in {
  tf.core.configuration = {
    terraform.backend.http = let
      vbk =
        "https://vbk.infra.aws.iohkdev.io/state/${config.cluster.name}/core";
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
          (name: role: { arn = var "aws_iam_role.${role.uid}.arn"; });

        instances = lib.flip lib.mapAttrs config.cluster.instances
          (name: server: {
            flake-attr =
              "nixosConfigurations.${server.uid}.config.system.build.toplevel";
            instance-type = var "aws_instance.${server.name}.instance_type";
            name = server.name;
            private-ip = var "aws_instance.${server.name}.private_ip";
            public-ip = var "aws_instance.${server.name}.public_ip";
            tags = server.tags;
            uid = server.uid;
          });

        asgs = { };
      };
    };

    provider = {
      aws = [{ region = config.cluster.region; }] ++ (lib.forEach regions
        (region: {
          inherit region;
          alias = awsProviderNameFor region;
        }));
    };

    resource.tls_private_key.${config.cluster.name} =
      lib.mkIf config.cluster.generateSSHKey {
        algorithm = "RSA";
        rsa_bits = 4096;
      };

    resource.aws_key_pair.core = {
      provider = awsProviderFor config.cluster.region;
      key_name = "${config.cluster.name}-core";
      public_key =
        var "tls_private_key.${config.cluster.name}.public_key_openssh";
    };

    data.aws_route53_zone.selected = lib.mkIf config.cluster.route53 {
      provider = "aws.us_east_2";
      name = "${config.cluster.domain}.";
    };

    resource.aws_iam_instance_profile =
      lib.flip lib.mapAttrs' config.cluster.instances (name: instance:
        lib.nameValuePair instance.uid {
          name = instance.uid;
          path = instance.iam.instanceProfile.path;
          role = instance.iam.instanceProfile.role.tfName;
          lifecycle = [{ create_before_destroy = true; }];
        });

    resource.aws_iam_role = lib.flip lib.mapAttrs' config.cluster.iam.roles
      (roleName: role:
        lib.nameValuePair role.uid {
          name = role.uid;
          assume_role_policy = role.assumePolicy.tfJson;
          lifecycle = [{ create_before_destroy = true; }];
        });

    resource.aws_iam_role_policy = lib.listToAttrs (lib.flatten
      (lib.flip lib.mapAttrsToList config.cluster.iam.roles (roleName: role:
        lib.flip lib.mapAttrsToList role.policies (policyName: policy:
          lib.nameValuePair policy.uid {
            name = policy.uid;
            role = role.id;
            policy = var "data.aws_iam_policy_document.${policy.uid}.json";
          }))));

    data.aws_iam_policy_document = lib.listToAttrs (lib.flatten
      (lib.flip lib.mapAttrsToList config.cluster.iam.roles (roleName: role:
        lib.flip lib.mapAttrsToList role.policies (policyName: policy:
          lib.nameValuePair policy.uid {
            statement = {
              inherit (policy) effect actions resources;
            } // (lib.optionalAttrs (policy.condition != null) {
              inherit (policy) condition;
            });
          }))));

    data.aws_vpc = (mapVpcs (vpc:
      lib.nameValuePair vpc.region {
        provider = awsProviderFor vpc.region;
        filter = {
          name = "tag:Name";
          values = [ vpc.name ];
        };
      })) // {
        core = {
          provider = awsProviderFor config.cluster.region;
          filter = {
            name = "tag:Name";
            values = [ config.cluster.vpc.name ];
          };
        };
      };

    resource.aws_security_group = {
      "${config.cluster.name}" = {
        provider = awsProviderFor config.cluster.region;
        name_prefix = "${config.cluster.name}-";
        description = "Security group for Core in ${config.cluster.name}";
        vpc_id = id "data.aws_vpc.core";
        lifecycle = [{ create_before_destroy = true; }];
      };
    };

    resource.aws_security_group_rule = let
      mapInstances = _: instance:
        merge (lib.flip lib.mapAttrsToList instance.securityGroupRules (_: rule:
          lib.listToAttrs (lib.flatten (lib.flip map rule.protocols (protocol:
            mkSecurityGroupRule {
              prefix = config.cluster.name;
              inherit (config.cluster) region;
              inherit rule protocol;
            })))));

      instances = lib.mapAttrsToList mapInstances config.cluster.instances;
    in merge instances;

    resource.aws_eip = lib.mapAttrs' (name: server:
      lib.nameValuePair server.uid {
        vpc = true;
        network_interface = id "aws_network_interface.${server.uid}";
        associate_with_private_ip = server.privateIP;
        tags = {
          Cluster = config.cluster.name;
          Name = server.name;
        };
        lifecycle = [{ create_before_destroy = true; }];
      }) config.cluster.instances;

    resource.aws_network_interface = lib.mapAttrs' (name: server:
      lib.nameValuePair server.uid {
        subnet_id = server.subnet.id;
        security_groups = [ server.securityGroupId ];
        private_ips = [ server.privateIP ];
        tags = {
          Cluster = config.cluster.name;
          Name = server.name;
        };
        lifecycle = [{ create_before_destroy = true; }];
      }) config.cluster.instances;

    resource.aws_subnet = lib.flip lib.mapAttrs' config.cluster.vpc.subnets
      (name: subnet:
        lib.nameValuePair subnet.name {
          provider = awsProviderFor config.cluster.vpc.region;
          vpc_id = id "data.aws_vpc.core";
          cidr_block = subnet.cidr;
          tags = {
            Cluster = config.cluster.name;
            Name = subnet.name;
          };
          lifecycle = [{ create_before_destroy = true; }];
        });

    resource.aws_internet_gateway.${config.cluster.name} = {
      vpc_id = id "data.aws_vpc.core";
      tags = {
        Cluster = config.cluster.name;
        Name = config.cluster.name;
      };
      lifecycle = [{ create_before_destroy = true; }];
    };

    data.aws_vpc_peering_connection = mapVpcs (vpc:
      lib.nameValuePair vpc.region {
        status = "active";
        tags = { Name = vpc.name; };
      });

    resource.aws_route_table.${config.cluster.name} = {
      vpc_id = id "data.aws_vpc.core";
      route = [
        (nullRoute // {
          cidr_block = "0.0.0.0/0";
          gateway_id = id "aws_internet_gateway.${config.cluster.name}";
        })
      ] ++ (mapVpcsToList (vpc:
        nullRoute // {
          cidr_block = vpc.cidr;
          vpc_peering_connection_id =
            id "data.aws_vpc_peering_connection.${vpc.region}";
        }));

      tags = {
        Cluster = config.cluster.name;
        Name = config.cluster.name;
      };
      lifecycle = [{ create_before_destroy = true; }];
    };

    resource.aws_route_table_association = lib.mapAttrs' (name: subnet:
      lib.nameValuePair "${config.cluster.name}-${name}-internet" {
        subnet_id = subnet.id;
        route_table_id = id "aws_route_table.${config.cluster.name}";
      }) config.cluster.vpc.subnets;

    resource.aws_route53_record = lib.mkIf config.cluster.route53 (let
      domains = (lib.flatten
        (lib.flip lib.mapAttrsToList config.cluster.instances
          (instanceName: instance:
            lib.forEach instance.route53.domains
            (domain: { ${domain} = instance.uid; }))));
    in lib.flip lib.mapAttrs' (lib.zipAttrs domains) (domain: instanceUids:
      lib.nameValuePair "${config.cluster.name}-${
        lib.replaceStrings [ "." "*" ] [ "_" "_" ] domain
      }" {
        zone_id = id "data.aws_route53_zone.selected";
        name = domain;
        type = "A";
        ttl = "60";
        records =
          lib.forEach instanceUids (uid: var "aws_eip.${uid}.public_ip");
      }));

    resource.tls_private_key.private_key = { algorithm = "RSA"; };

    resource.local_file = {
      "ssh-${config.cluster.name}" = lib.mkIf config.cluster.generateSSHKey {
        filename = "secrets/ssh-${config.cluster.name}";
        sensitive_content =
          var "tls_private_key.${config.cluster.name}.private_key_pem";
        file_permission = "0600";
      };
      "ssh-${config.cluster.name}-pub" =
        lib.mkIf config.cluster.generateSSHKey {
          filename = "secrets/ssh-${config.cluster.name}.pub";
          content =
            var "tls_private_key.${config.cluster.name}.public_key_openssh";
        };
    };

    resource.aws_instance = lib.mapAttrs (name: server:
      lib.mkMerge [
        (lib.mkIf server.enable {
          ami = server.ami;
          instance_type = server.instanceType;
          monitoring = true;

          tags = {
            Cluster = config.cluster.name;
            Name = name;
            UID = server.uid;
            Consul = "server";
            Vault = "server";
            Nomad = "server";
            # Flake = server.flake;
          } // server.tags;

          root_block_device = {
            volume_type = "gp2";
            volume_size = server.volumeSize;
            delete_on_termination = true;
          };

          iam_instance_profile = server.iam.instanceProfile.tfName;

          network_interface = {
            network_interface_id = id "aws_network_interface.${server.uid}";
            device_index = 0;
          };

          user_data = server.userData;

          provisioner = [
            {
              local-exec = {
                command = "${
                    self.nixosConfigurations."${config.cluster.name}-${name}".config.secrets.generateScript
                  }/bin/generate-secrets";

                environment = { IP = var "self.public_ip"; };
              };
            }
            {
              local-exec = {
                inherit (server.localProvisioner)
                  interpreter command environment;
                working_dir = server.localProvisioner.workingDir;
              };
            }
          ];
        })

        (lib.mkIf config.cluster.generateSSHKey {
          key_name = var "aws_key_pair.core.key_name";
        })
      ]) config.cluster.instances;
  };
}
