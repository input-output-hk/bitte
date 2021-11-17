{ self, lib, pkgs, config, terralib, ... }:
let
  inherit (terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute;

  merge = lib.foldl' lib.recursiveUpdate { };
  tags = { Cluster = config.cluster.name; };
in
{
  tf.core.configuration = {
    terraform.backend.http =
      let
        vbk =
          "https://vbk.infra.aws.iohkdev.io/state/${config.cluster.name}/core";
      in
      {
        address = vbk;
        lock_address = vbk;
        unlock_address = vbk;
      };

    terraform.required_providers = pkgs.terraform-provider-versions;

    provider = {
      acme = {
        server_url = "https://acme-v02.api.letsencrypt.org/directory";
      };

      aws = [{ region = config.cluster.region; }] ++ (lib.forEach regions
        (region: {
          inherit region;
          alias = awsProviderNameFor region;
        }));
    };

    # ---------------------------------------------------------------
    # Networking
    # ---------------------------------------------------------------

    resource.aws_vpc.core = {
      provider = awsProviderFor config.cluster.region;
      lifecycle = [{ create_before_destroy = true; }];

      cidr_block = config.cluster.vpc.cidr;
      enable_dns_hostnames = true;
      tags = {
        Cluster = config.cluster.name;
        Name = config.cluster.vpc.name;
        Region = config.cluster.region;
      };
    };

    resource.aws_internet_gateway."${config.cluster.name}" = {
      lifecycle = [{ create_before_destroy = true; }];

      vpc_id = id "aws_vpc.core";
      tags = {
        Cluster = config.cluster.name;
        Name = config.cluster.name;
      };
    };

    resource.aws_route_table."${config.cluster.name}" = {
      vpc_id = id "aws_vpc.core";
      lifecycle = [{ create_before_destroy = true; }];

      tags = {
        Cluster = config.cluster.name;
        Name = config.cluster.name;
      };
    };

    resource.aws_route.core = nullRoute // {
      route_table_id = id "aws_route_table.${config.cluster.name}";
      destination_cidr_block = "0.0.0.0/0";
      gateway_id = id "aws_internet_gateway.${config.cluster.name}";
    };

    resource.aws_subnet = lib.flip lib.mapAttrs' config.cluster.vpc.subnets (name: subnet:
      lib.nameValuePair subnet.name {
        provider = awsProviderFor config.cluster.vpc.region;
        vpc_id = id "aws_vpc.core";
        cidr_block = subnet.cidr;

        lifecycle = [{ create_before_destroy = true; }];

        tags = {
          Cluster = config.cluster.name;
          Name = subnet.name;
        };
      }
    );

    resource.aws_route_table_association = lib.mapAttrs'
      (name: subnet:
        lib.nameValuePair "${config.cluster.name}-${name}-internet" {
          subnet_id = subnet.id;
          route_table_id = id "aws_route_table.${config.cluster.name}";
        }
      )
      config.cluster.vpc.subnets
    ;

    # ---------------------------------------------------------------
    # DNS
    # ---------------------------------------------------------------

    data.aws_route53_zone.selected = lib.mkIf config.cluster.route53 {
      provider = "aws.us_east_2";
      name = "${config.cluster.domain}.";
    };

    resource.aws_route53_record = lib.mkIf config.cluster.route53 (
      let
        domains = (lib.flatten
          (lib.flip lib.mapAttrsToList config.cluster.instances
            (instanceName: instance:
              lib.forEach instance.route53.domains
                (domain: { ${domain} = instance.uid; }))));
      in
      lib.flip lib.mapAttrs' (lib.zipAttrs domains) (domain: instanceUids:
        lib.nameValuePair "${config.cluster.name}-${
        lib.replaceStrings [ "." "*" ] [ "_" "_" ] domain
      }"
          {
            zone_id = id "data.aws_route53_zone.selected";
            name = domain;
            type = "A";
            ttl = "60";
            records =
              lib.forEach instanceUids (uid: var "aws_eip.${uid}.public_ip");
          })
    );

    # ---------------------------------------------------------------
    # SSL/TLS - root ssh
    # ---------------------------------------------------------------

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

    # ---------------------------------------------------------------
    # Core Instance IAM + Security Group
    # ---------------------------------------------------------------

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

    resource.aws_security_group = {
      "${config.cluster.name}" = {
        provider = awsProviderFor config.cluster.region;
        name_prefix = "${config.cluster.name}-";
        description = "Security group for Core in ${config.cluster.name}";
        vpc_id = id "aws_vpc.core";
        lifecycle = [{ create_before_destroy = true; }];
      };
    };

    resource.aws_security_group_rule =
      let
        mapInstances = _: instance:
          merge (lib.flip lib.mapAttrsToList instance.securityGroupRules (_: rule:
            lib.listToAttrs (lib.flatten (lib.flip map rule.protocols (protocol:
              mkSecurityGroupRule {
                prefix = config.cluster.name;
                inherit (config.cluster) region;
                inherit rule protocol;
              })))));

        instances = lib.mapAttrsToList mapInstances config.cluster.instances;
      in
      merge instances;

    # ---------------------------------------------------------------
    # Core Instances
    # ---------------------------------------------------------------

    resource.aws_eip = lib.mapAttrs'
      (name: server:
        lib.nameValuePair server.uid {
          vpc = true;
          network_interface = id "aws_network_interface.${server.uid}";
          associate_with_private_ip = server.privateIP;
          tags = {
            Cluster = config.cluster.name;
            Name = server.name;
          };
          lifecycle = [{ create_before_destroy = true; }];
        })
      config.cluster.instances;

    resource.aws_network_interface = lib.mapAttrs'
      (name: server:
        lib.nameValuePair server.uid {
          subnet_id = server.subnet.id;
          security_groups = [ server.securityGroupId ];
          private_ips = [ server.privateIP ];
          tags = {
            Cluster = config.cluster.name;
            Name = server.name;
          };
          lifecycle = [{ create_before_destroy = true; }];
        })
      config.cluster.instances;

    resource.aws_instance = lib.mapAttrs
      (name: server:
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

            ebs_optimized =
              lib.mkIf (server.ebsOptimized != null) server.ebsOptimized;

            provisioner = [
              {
                local-exec = {
                  command = "${
                    self.nixosConfigurations."${config.cluster.name}-${name}".config.secrets.generateScript
                  }/bin/generate-secrets";
                };
              }
              {
                local-exec =
                  let
                    command = server.localProvisioner.protoCommand (var "self.public_ip");
                  in
                  {
                    inherit command;
                    inherit (server.localProvisioner)
                      interpreter environment;
                    working_dir = server.localProvisioner.workingDir;
                  };
              }
            ];
          })

          (lib.mkIf config.cluster.generateSSHKey {
            key_name = var "aws_key_pair.core.key_name";
          })
        ])
      config.cluster.instances;
  };
}
