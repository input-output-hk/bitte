{ self, lib, pkgs, config, ... }:
let
  inherit (lib) types;
  inherit (pkgs.terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute;
  vpcs = pkgs.terralib.vpcs config.cluster;

  merge = lib.foldl' lib.recursiveUpdate { };
in {
  options = {
    tf = lib.mkOption {
      default = { };
      type = types.attrsOf (types.submodule ({ name, ... }@this: {
        options = {
          configuration =
            lib.mkOption { type = types.attrsOf types.unspecified; };
          output = lib.mkOption {
            type = lib.mkOptionType { name = "config.tf.json"; };
            apply = v:
              let
                compiledConfig =
                  import (self.inputs.terranix + "/core/default.nix") {
                    pkgs = self.inputs.nixpkgs.legacyPackages.x86_64-linux;
                    strip_nulls = false;
                    terranix_config = {
                      imports = [ this.config.configuration ];
                    };
                  };
              in pkgs.toPrettyJSON "${name}.tf" compiledConfig.config;
          };
        };
      }));
    };
  };

  config = {
    tf = {
      core.configuration = {
        terraform.backend.remote = {
          organization = "iohk-midnight";
          workspaces = [{ prefix = "${config.cluster.name}_"; }];
        };

        output.cluster = {
          value = {
            flake = toString config.cluster.flakePath;
            nix = pkgs.nixFlakes;
            kms = config.cluster.kms;
            region = config.cluster.region;
            name = config.cluster.name;

            roles = lib.flip lib.mapAttrs config.cluster.iam.roles
              (name: role: { arn = var "aws_iam_role.${role.uid}.arn"; });

            instances = lib.flip lib.mapAttrs config.cluster.instances
              (name: server: {
                flake_attr =
                  "nixosConfigurations.${server.uid}.config.system.build.toplevel";
                instance_type = var "aws_instance.${server.name}.instance_type";
                name = server.name;
                private_ip = var "aws_instance.${server.name}.private_ip";
                public_ip = var "aws_instance.${server.name}.public_ip";
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

        data.aws_vpc = (lib.flip lib.mapAttrs' vpcs (region: vpc:
          lib.nameValuePair region {
            inherit (vpc) provider;
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
            merge (lib.flip lib.mapAttrsToList instance.securityGroupRules
              (_: rule:
                lib.listToAttrs (lib.flatten (lib.flip map rule.protocols
                  (protocol:
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

        data.aws_vpc_peering_connection = lib.flip lib.mapAttrs' vpcs
          (region: vpc:
            lib.nameValuePair region { tags = { Name = vpc.name; }; });

        resource.aws_route_table.${config.cluster.name} = {
          vpc_id = id "data.aws_vpc.core";
          route = [{
            cidr_block = "0.0.0.0/0";
            gateway_id = id "aws_internet_gateway.${config.cluster.name}";
            egress_only_gateway_id = null;
            instance_id = null;
            ipv6_cidr_block = null;
            nat_gateway_id = null;
            network_interface_id = null;
            transit_gateway_id = null;
            vpc_peering_connection_id = null;
          }] ++ (lib.flip lib.mapAttrsToList vpcs (innerRegion: vpc:
            nullRoute // {
              inherit (vpc) cidr_block;
              vpc_peering_connection_id =
                id "data.aws_vpc_peering_connection.${innerRegion}";
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
                (subDomain: { ${subDomain} = instance.uid; }))));
        in lib.flip lib.mapAttrs' (lib.zipAttrs domains)
        (subDomain: instanceUids:
          lib.nameValuePair "${config.cluster.name}-${
            lib.replaceStrings [ "." ] [ "_" ] subDomain
          }" {
            zone_id = id "data.aws_route53_zone.selected";
            name = "${subDomain}.${config.cluster.domain}";
            type = "A";
            ttl = "60";
            records =
              lib.forEach instanceUids (uid: var "aws_eip.${uid}.public_ip");
          }));

        provider.acme = {
          # server_url = "https://acme-staging-v02.api.letsencrypt.org/directory";
          server_url = "https://acme-v02.api.letsencrypt.org/directory";
        };

        resource.tls_private_key.private_key = { algorithm = "RSA"; };

        resource.acme_registration.reg = {
          account_key_pem = var "tls_private_key.private_key.private_key_pem";
          email_address = "michael.fellinger@iohk.io";
        };

        resource.acme_certificate.certificate = {
          account_key_pem = var "acme_registration.reg.account_key_pem";
          common_name = "${config.cluster.domain}";
          subject_alternative_names = [ "*.${config.cluster.domain}" ];

          dns_challenge.provider = "route53";
        };

        resource.null_resource = lib.flip lib.mapAttrs' config.cluster.instances
          (name: server:
            lib.nameValuePair "${name}-files" {
              triggers = {
                private_key =
                  var "acme_certificate.certificate.private_key_pem";
                cert_pem = var "acme_certificate.certificate.certificate_pem";
                issuer_pem = var "acme_certificate.certificate.issuer_pem";
                target_arn = var "aws_instance.${name}.arn";
              };

              connection = {
                type = "ssh";
                host = var "aws_instance.${name}.public_ip";
                private_key =
                  var "tls_private_key.${config.cluster.name}.private_key_pem";
                agent = false;
              };

              provisioner = [
                {
                  file = {
                    content =
                      var "acme_certificate.certificate.private_key_pem";
                    destination =
                      "/etc/ssl/certs/${config.cluster.domain}-key.pem";
                  };
                }
                {
                  file = {
                    content =
                      var "acme_certificate.certificate.certificate_pem";
                    destination =
                      "/etc/ssl/certs/${config.cluster.domain}-cert.pem";
                  };
                }
                {
                  file = {
                    content = var "acme_certificate.certificate.issuer_pem";
                    destination =
                      "/etc/ssl/certs/${config.cluster.domain}-ca.pem";
                  };
                }
              ];
            });

        resource.local_file = {
          "ssh-${config.cluster.name}" =
            lib.mkIf config.cluster.generateSSHKey {
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

              provisioner = [{
                local-exec = {
                  inherit (server.localProvisioner)
                    interpreter command environment;
                  working_dir = server.localProvisioner.workingDir;
                };
              }];

              # provisioner = let
              #   connection = {
              #     type = "ssh";
              #     host = var "self.public_ip";
              #     private_key = var "tls_private_key.${config.cluster.name}.private_key_pem";
              #     agent = false;
              #   };
              # in
              # [
              #   {
              #     file = {
              #       content = var "file(./encrypted/core-1/vault.enc.json.json)";
              #       destination = "/run/keys/ca.crt.pem";
              #       inherit connection;
              #     };
              #   }
              # ];

              #   {
              #     file = {
              #       content = var "tls_locally_signed_cert.cert.cert_pem";
              #       destination = "/run/keys/vault.crt.pem";
              #       inherit connection;
              #     };
              #   }
              #   {
              #     file = {
              #       content = var "tls_private_key.cert.private_key_pem";
              #       destination = "/run/keys/vault.key.pem";
              #       inherit connection;
              #     };
              #   }
              #   {
              #     local-exec = {
              #       inherit (server.localProvisioner)
              #         interpreter command environment;
              #       working_dir = server.localProvisioner.workingDir;
              #     };
              #   }
              # ];

            })

            (lib.mkIf config.cluster.generateSSHKey {
              key_name = var "aws_key_pair.core.key_name";
            })
          ]) config.cluster.instances;
      };

    };
  };
}
