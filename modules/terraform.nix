{ self, config, nodeName, ... }:
let
  pkgs = import self.inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [ self.overlay.x86_64-linux ];
  };
  inherit (builtins) toJSON attrNames elemAt;
  inherit (pkgs.lib)
    mkOption mkIf replaceStrings readFile optionalAttrs mapAttrs mkMerge
    mapAttrsToList mapAttrs' nameValuePair flip foldl' recursiveUpdate
    listToAttrs flatten optional mkOptionType imap0 mkEnableOption forEach
    remove reverseList head tail splitString zipAttrs;
  inherit (pkgs.lib.types)
    attrs submodule str attrsOf bool ints path enum port listof nullOr listOf
    oneOf list package;
  inherit (pkgs.terralib) var id pp;

  kms2region = kms: elemAt (splitString ":" kms) 3;

  amis = let
    nixosAmis = import
      (self.inputs.nixpkgs + "/nixos/modules/virtualisation/ec2-amis.nix");
  in {
    nixos = mapAttrs' (name: value: nameValuePair name value.hvm-ebs)
      nixosAmis."20.03";
  };

  cfg = config.cluster;
  resources = config.terraform.resource;

  clusterType = submodule ({ ... }: {
    options = {
      name = mkOption { type = str; };

      domain = mkOption { type = str; };

      secrets = mkOption { type = path; };

      instances = mkOption {
        type = attrsOf serverType;
        default = { };
      };

      autoscalingGroups = mkOption {
        type = attrsOf autoscalingGroupType;
        default = { };
      };

      route53 = mkOption {
        type = bool;
        default = true;
        description = "Enable route53 registrations";
      };

      ami = mkOption {
        type = str;
        default = amis.nixos.${cfg.region};
      };

      iam = mkOption {
        type = clusterIamType;
        default = { };
      };

      kms = mkOption { type = str; };

      s3-bucket = mkOption { type = str; };

      adminNames = mkOption { type = listOf str; default = []; };

      generateSSHKey = mkOption {
        type = bool;
        default = true;
      };

      region = mkOption {
        type = str;
        default = kms2region cfg.kms;
      };

      vpc = mkOption {
        type = vpcType;
        default = {
          cidr = "10.0.0.0/16";

          subnets = {
            prv-1.cidr = "10.0.0.0/19";
            prv-2.cidr = "10.0.32.0/19";
            prv-3.cidr = "10.0.64.0/19";
          };
        };
      };

      certificate = mkOption {
        type = certificateType;
        default = { };
      };
    };
  });

  clusterIamType = submodule {
    options = {
      roles = mkOption {
        type = attrsOf iamRoleType;
        default = { };
      };
    };
  };

  iamRoleType = submodule ({ name, ... }@this: {
    options = {
      id = mkOption {
        type = str;
        default = id "aws_iam_role.${this.config.uid}";
      };

      uid = mkOption {
        type = str;
        default = "${cfg.name}-${this.config.name}";
      };

      name = mkOption {
        type = str;
        default = name;
      };

      tfName = mkOption {
        type = str;
        default = var "aws_iam_role.${this.config.uid}.name";
      };

      assumePolicy = mkOption {
        type = iamRoleAssumePolicyType;
        default = { };
      };

      policies = mkOption {
        type = attrsOf (iamRolePolicyType this.config.uid);
        default = { };
      };
    };
  });

  iamRolePolicyType = parentUid:
    (submodule ({ name, ... }@this: {
      options = {
        uid = mkOption {
          type = str;
          default = "${parentUid}-${this.config.name}";
        };

        name = mkOption {
          type = str;
          default = name;
        };

        effect = mkOption {
          type = enum [ "Allow" "Deny" ];
          default = "Allow";
        };

        actions = mkOption { type = listOf str; };

        resources = mkOption { type = listOf str; };

        condition = mkOption {
          type = nullOr (listOf attrs);
          default = null;
        };
      };
    }));

  iamRoleAssumePolicyType = submodule ({ ... }@this: {
    options = {
      tfJson = mkOption {
        type = str;
        apply = _:
          toJSON {
            Version = "2012-10-17";
            Statement = [{
              Effect = this.config.effect;
              Principal.Service = this.config.principal.service;
              Action = this.config.action;
              Sid = "";
            }];
          };
      };

      effect = mkOption {
        type = enum [ "Allow" "Deny" ];
        default = "Allow";
      };

      action = mkOption { type = str; };

      principal = mkOption { type = iamRolePrincipalsType; };
    };
  });

  iamRolePrincipalsType =
    submodule { options = { service = mkOption { type = str; }; }; };

  certificateType = submodule ({ ... }@this: {
    options = {
      organization = mkOption {
        type = str;
        default = "IOHK";
      };

      commonName = mkOption {
        type = str;
        default = this.config.organization;
      };

      validityPeriodHours = mkOption {
        type = ints.positive;
        default = 8760;
      };
    };
  });

  securityGroupRuleType = { defaultSecurityGroupId }:
    submodule ({ name, ... }@this: {
      options = {
        name = mkOption {
          type = str;
          default = name;
        };

        type = mkOption {
          type = enum [ "ingress" "egress" ];
          default = "ingress";
        };

        port = mkOption {
          type = nullOr port;
          default = null;
        };

        from = mkOption {
          type = port;
          default = this.config.port;
        };

        to = mkOption {
          type = port;
          default = this.config.port;
        };

        protocols = mkOption {
          type = listOf (enum [ "tcp" "udp" "-1" ]);
          default = [ "tcp" ];
        };

        cidrs = mkOption {
          type = listOf str;
          default = [ ];
        };

        securityGroupId = mkOption {
          type = str;
          default = defaultSecurityGroupId;
        };

        self = mkOption {
          type = bool;
          default = false;
        };

        sourceSecurityGroupId = mkOption {
          type = nullOr str;
          default = null;
        };
      };
    });

  vpcType = submodule {
    options = {
      name = mkOption {
        type = str;
        default = cfg.name;
      };

      cidr = mkOption { type = str; };

      id = mkOption {
        type = str;
        default = id "aws_vpc.${cfg.name}";
      };

      subnets = mkOption {
        type = attrsOf subnetType;
        default = { };
      };
    };
  };

  subnetType = submodule ({ name, ... }: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      cidr = mkOption { type = str; };

      id = mkOption {
        type = str;
        default = id "aws_subnet.${cfg.name}-${name}";
      };
    };
  });

  serverIamType = parentName:
    submodule {
      options = {
        role = mkOption { type = iamRoleType; };

        instanceProfile = mkOption { type = instanceProfileType parentName; };
      };
    };

  instanceProfileType = parentName:
    submodule {
      options = {
        tfName = mkOption {
          type = str;
          readOnly = true;
          default =
            var "aws_iam_instance_profile.${cfg.name}-${parentName}.name";
        };

        tfArn = mkOption {
          type = str;
          readOnly = true;
          default =
            var "aws_iam_instance_profile.${cfg.name}-${parentName}.arn";
        };

        role = mkOption { type = iamRoleType; };

        path = mkOption {
          type = str;
          default = "/";
        };
      };
    };

  serverType = submodule ({ name, ... }@this: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      uid = mkOption {
        type = str;
        default = "${cfg.name}-${name}";
      };

      enable = mkOption {
        type = bool;
        default = true;
      };

      domain = mkOption {
        type = str;
        default = "${this.config.name}.${cfg.domain}";
      };

      modules = mkOption {
        type = listOf path;
        default = [ ];
      };

      ami = mkOption {
        type = str;
        default = config.cluster.ami;
      };

      iam = mkOption {
        type = serverIamType this.config.name;
        default = {
          role = cfg.iam.roles.core;
          instanceProfile.role = cfg.iam.roles.core;
        };
      };

      route53 = mkOption {
        default = { domains = [ ]; };
        type = submodule {
          options = {
            domains = mkOption {
              type = listOf str;
              default = [ ];
            };
          };
        };
      };

      userData = mkOption {
        type = nullOr str;
        default = ''
          ### https://nixos.org/channels/nixpkgs-unstable nixos
          { pkgs, config, ... }: {
            imports = [ <nixpkgs/nixos/modules/virtualisation/amazon-image.nix> ];

            nix = {
              package = pkgs.nixFlakes;
              extraOptions = '''
                show-trace = true
                experimental-features = nix-command flakes ca-references
              ''';
              binaryCaches = [
                "https://hydra.iohk.io"
                "https://manveru.cachix.org"
              ];
              binaryCachePublicKeys = [
                "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
                "manveru.cachix.org-1:L5nJHSinfA2K5dDCG3KAEadwf/e3qqhuBr7yCwSksXo="
              ];
            };

            # Needed to give backed up certs the right permissions
            services.nginx.enable = true;

            environment.etc.ready.text = "true";
          }
        '';
      };

      # Gotta do it this way since TF outputs aren't generated at this point and we need the IP.
      localProvisioner = mkOption {
        type = localExecType;
        default = let
          ip = var "aws_eip.${this.config.uid}.public_ip";
          args = [
            "${pkgs.bitte}/bin/bitte"
            "provision"
            "--name"
            this.config.name
            "--cluster"
            cfg.name
            "--ip"
            ip
          ];
          rev = reverseList args;
          command = head rev;
          interpreter = reverseList (tail rev);
        in { inherit command interpreter; };
      };

      postDeploy = mkOption {
        type = localExecType;
        default = {
          # command = name;
          # interpreter = let
          #   ip = var "aws_eip.${this.config.uid}.public_ip";
          # in [
          #   "${pkgs.bitte}/bin/bitte"
          #   "deploy"
          #   "--cluster"
          #   "${cfg.name}"
          #   "--ip"
          #   "${ip}"
          #   "--flake"
          #   "${this.config.flake}"
          #   "--flake-host"
          #   "${name}"
          #   "--name"
          #   "${this.config.uid}"
          # ];
        };
      };

      instanceType = mkOption { type = str; };

      tags = mkOption {
        type = attrsOf str;
        default = {
          Cluster = cfg.name;
          Name = this.config.name;
          UID = this.config.uid;
          Consul = "server";
          Vault = "server";
          Nomad = "server";
        };
      };

      privateIP = mkOption { type = str; };

      # flake = mkOption { type = str; };

      subnet = mkOption {
        type = subnetType;
        default = { };
      };

      volumeSize = mkOption {
        type = ints.positive;
        default = 30;
      };

      securityGroupId = mkOption {
        type = str;
        default = id "aws_security_group.${cfg.name}-core";
      };

      securityGroupRules = mkOption {
        type = attrsOf (securityGroupRuleType {
          defaultSecurityGroupId = this.config.securityGroupId;
        });
        default = { };
      };
    };
  });

  localExecType = submodule {
    options = {
      command = mkOption { type = str; };

      workingDir = mkOption {
        type = nullOr path;
        default = null;
      };

      interpreter = mkOption {
        type = nullOr (listOf str);
        default = [ "${pkgs.bash}/bin/bash" "-c" ];
      };

      environment = mkOption {
        type = attrsOf str;
        default = { };
      };
    };
  };

  autoscalingGroupType = submodule ({ name, ... }@this: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      modules = mkOption {
        type = listOf path;
        default = [ ];
      };

      ami = mkOption {
        type = str;
        default = config.cluster.ami;
      };

      iam = mkOption { type = serverIamType this.config.name; };

      userData = mkOption {
        type = nullOr str;
        default = ''
          ### https://nixos.org/channels/nixpkgs-unstable nixos
          { pkgs, config, ... }: {
            imports = [ <nixpkgs/nixos/modules/virtualisation/amazon-image.nix> ];

            nix = {
              package = pkgs.nixFlakes;
              extraOptions = '''
                show-trace = true
                experimental-features = nix-command flakes ca-references
              ''';
              binaryCaches = [
                "https://hydra.iohk.io"
                "https://manveru.cachix.org"
              ];
              binaryCachePublicKeys = [
                "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
                "manveru.cachix.org-1:L5nJHSinfA2K5dDCG3KAEadwf/e3qqhuBr7yCwSksXo="
              ];
            };

            systemd.services.install = {
              wantedBy = ["multi-user.target"];
              after = ["network-online.target"];
              path = with pkgs; [ config.system.build.nixos-rebuild awscli coreutils gnutar curl xz ];
              restartIfChanged = false;
              unitConfig.X-StopOnRemoval = false;
              serviceConfig = {
                Type = "oneshot";
                Restart = "on-failure";
                RestartSec = "30s";
              };
              script = '''
                set -exuo pipefail
                pushd /run/keys

                aws s3 cp \
                  "s3://${cfg.s3-bucket}/infra/secrets/${cfg.name}/${cfg.kms}/source/source.tar.xz" \
                  source.tar.xz
                mkdir -p source
                tar xvf source.tar.xz -C source
                nixos-rebuild --flake ./source#${cfg.name}-${this.config.name} boot
                booted="$(readlink /run/booted-system/{initrd,kernel,kernel-modules})"
                built="$(readlink /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules})"
                if [ "$booted" = "$built" ]; then
                  nixos-rebuild --flake ./source#${cfg.name}-${this.config.name} switch
                else
                  /run/current-system/sw/bin/shutdown -r now
                fi
              ''';
            };
          }
        '';
      };

      minSize = mkOption {
        type = ints.unsigned;
        default = 0;
      };

      maxSize = mkOption {
        type = ints.unsigned;
        default = 10;
      };

      desiredCapacity = mkOption {
        type = ints.unsigned;
        default = 1;
      };

      maxInstanceLifetime = mkOption {
        type = oneOf [ (enum [ 0 ]) (ints.between 604800 31536000) ];
        default = 0;
      };

      instanceType = mkOption {
        type = str;
        default = "t3a.medium";
      };

      tags = mkOption {
        type = attrsOf str;
        default = { };
      };

      associatePublicIP = mkOption {
        type = bool;
        default = false;
      };

      uid = mkOption {
        type = str;
        default = "${cfg.name}-${name}";
      };

      subnets = mkOption {
        type = listOf subnetType;
        default = [ ];
      };

      securityGroupId = mkOption {
        type = str;
        default = id "aws_security_group.${this.config.uid}";
      };

      securityGroupRules = mkOption {
        type = attrsOf (securityGroupRuleType {
          defaultSecurityGroupId = this.config.securityGroupId;
        });
        default = { };
      };
    };
  });
in {
  options = {
    cluster = mkOption {
      type = clusterType;
      default = { };
    };

    terraform = mkOption {
      type = attrs;
      default = { };
    };

    instance = mkOption {
      type = attrs;
      default = cfg.instances.${nodeName};
    };
  };

  config = {
    terraform = {
      provider = {
        consul = {
          address = "https://consul.${cfg.domain}";
          datacenter = cfg.region;
        };

        aws = let
          regions = [
            "ap-east-1"
            "ap-northeast-1"
            "ap-northeast-2"
            "ap-south-1"
            "ap-southeast-1"
            "ap-southeast-2"
            "ca-central-1"
            "eu-central-1"
            "eu-north-1"
            "eu-west-1"
            "eu-west-2"
            "eu-west-3"
            "me-south-1"
            "sa-east-1"
            "us-east-1"
            "us-east-2"
            "us-west-1"
            "us-west-2"
          ];
        in [{ region = cfg.region; }] ++ (forEach regions (region: {
          inherit region;
          alias = replaceStrings [ "-" ] [ "_" ] region;
        }));
      };

      # resource.consul_intention = listToAttrs
      #   (forEach config.services.consul.intentions (intention:
      #     nameValuePair "${intention.sourceName}_${intention.destinationName}" {
      #       source_name = intention.sourceName;
      #       destination_name = intention.destinationName;
      #       action = intention.action;
      #     }));

      resource.local_file = {
        "ssh-${cfg.name}" = mkIf cfg.generateSSHKey {
          filename = "secrets/ssh-${cfg.name}";
          sensitive_content = var "tls_private_key.${cfg.name}.private_key_pem";
          file_permission = "0600";
        };
        "ssh-${cfg.name}-pub" = mkIf cfg.generateSSHKey {
          filename = "secrets/ssh-${cfg.name}.pub";
          content = var "tls_private_key.${cfg.name}.public_key_openssh";
        };
      };

      resource.tls_private_key.${cfg.name} = mkIf cfg.generateSSHKey {
        algorithm = "RSA";
        rsa_bits = 4096;
      };

      resource.aws_key_pair = mkIf (cfg.generateSSHKey) {
        ${cfg.name} = {
          key_name = cfg.name;
          public_key = var "tls_private_key.${cfg.name}.public_key_openssh";
        };
      };

      resource.aws_iam_instance_profile = mkMerge ([
        (flip mapAttrs' cfg.instances (name: instance:
          nameValuePair instance.uid {
            name = instance.uid;
            path = instance.iam.instanceProfile.path;
            role = instance.iam.instanceProfile.role.tfName;
            lifecycle = [{ create_before_destroy = true; }];
          }))
        (flip mapAttrs' cfg.autoscalingGroups (name: group:
          nameValuePair group.uid {
            name = group.uid;
            path = group.iam.instanceProfile.path;
            role = group.iam.instanceProfile.role.tfName;
            lifecycle = [{ create_before_destroy = true; }];
          }))
      ]);

      resource.aws_iam_role = flip mapAttrs' cfg.iam.roles (roleName: role:
        nameValuePair role.uid {
          name = role.uid;
          assume_role_policy = role.assumePolicy.tfJson;
          lifecycle = [{ create_before_destroy = true; }];
        });

      # iam.roles.<roleName>.policy.<policyName>.{effect,resources,actions}
      resource.aws_iam_role_policy = listToAttrs (flatten
        (flip mapAttrsToList cfg.iam.roles (roleName: role:
          flip mapAttrsToList role.policies (policyName: policy:
            nameValuePair policy.uid {
              name = policy.uid;
              role = role.id;
              policy = var "data.aws_iam_policy_document.${policy.uid}.json";
            }))));

      data.aws_iam_policy_document = listToAttrs (flatten
        (flip mapAttrsToList cfg.iam.roles (roleName: role:
          flip mapAttrsToList role.policies (policyName: policy:
            nameValuePair policy.uid {
              statement = {
                inherit (policy) effect actions resources;
              } // (optionalAttrs (policy.condition != null) {
                inherit (policy) condition;
              });
            }))));

      output.cluster = {
        value = {
          flake = self.outPath;
          nix = pkgs.nixFlakes;
          kms = cfg.kms;
          region = cfg.region;
          name = cfg.name;

          roles = flip mapAttrs cfg.iam.roles
            (name: role: { arn = var "aws_iam_role.${role.uid}.arn"; });

          instances = flip mapAttrs cfg.instances (name: server: {
            flake_attr =
              "nixosConfigurations.${server.uid}.config.system.build.toplevel";
            instance_type = var "aws_instance.${server.name}.instance_type";
            name = server.name;
            private_ip = var "aws_instance.${server.name}.private_ip";
            public_ip = var "aws_instance.${server.name}.public_ip";
            tags = server.tags;
            uid = server.uid;
          });

          asgs = flip mapAttrs cfg.autoscalingGroups (name: group: {
            flake_attr =
              "nixosConfigurations.${group.uid}.config.system.build.toplevel";
            instance_type =
              var "aws_launch_configuration.${group.uid}.instance_type";
            uid = group.uid;
            arn = var "aws_autoscaling_group.${group.uid}.arn";
          });
        };
      };

      resource.aws_instance = mapAttrs (name: server:
        mkMerge [
          (mkIf server.enable {
            ami = server.ami;
            instance_type = server.instanceType;
            monitoring = true;

            tags = {
              Cluster = cfg.name;
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
            #     private_key = var "tls_private_key.${cfg.name}.private_key_pem";
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

          (mkIf cfg.generateSSHKey {
            key_name = var "aws_key_pair.${cfg.name}.key_name";
          })
        ]) cfg.instances;

      resource.aws_autoscaling_group = mapAttrs' (name: group:
        nameValuePair group.uid {
          launch_configuration =
            var "aws_launch_configuration.${group.uid}.name";
          name_prefix = group.uid;

          vpc_zone_identifier = forEach group.subnets (subnet: subnet.id);

          availability_zones = imap0 (idx: _:
            var "data.aws_availability_zones.available.names[${toString idx}]")
            group.subnets;

          min_size = group.minSize;
          max_size = group.maxSize;
          desired_capacity = group.desiredCapacity;

          health_check_type = "EC2";
          health_check_grace_period = 300;
          wait_for_capacity_timeout = "2m";
          termination_policies = [ "OldestLaunchTemplate" ];
          max_instance_lifetime = group.maxInstanceLifetime;

          tag = let
            tags = {
              Cluster = cfg.name;
              Name = group.name;
              UID = group.uid;
              Consul = "client";
              Vault = "client";
              Nomad = "client";
            } // group.tags;
          in mapAttrsToList (key: value: {
            inherit key value;
            propagate_at_launch = true;
          }) tags;

          lifecycle = [{ create_before_destroy = true; }];
        }) cfg.autoscalingGroups;

      resource.aws_launch_configuration = mapAttrs' (name: group:
        nameValuePair group.uid (mkMerge [
          {
            name_prefix = "${group.uid}-";
            image_id = group.ami;
            instance_type = group.instanceType;

            iam_instance_profile = group.iam.instanceProfile.tfName;

            security_groups = [ group.securityGroupId ];
            placement_tenancy = "default";
            # TODO: switch this to false for production
            associate_public_ip_address = group.associatePublicIP;

            ebs_optimized = false;

            root_block_device = {
              volume_type = "gp2";
              volume_size = 100;
              delete_on_termination = true;
            };

            lifecycle = [{ create_before_destroy = true; }];
          }

          (mkIf cfg.generateSSHKey {
            key_name = var "aws_key_pair.${cfg.name}.key_name";
          })

          (mkIf (group.userData != null) { user_data = group.userData; })
        ])) cfg.autoscalingGroups;

      resource.aws_security_group = mkMerge ([{
        "${cfg.name}-core" = {
          name_prefix = "${cfg.name}-core-";
          description = "Security group for Core in ${cfg.name}";
          vpc_id = cfg.vpc.id;
          lifecycle = [{ create_before_destroy = true; }];
        };
      }] ++ (mapAttrsToList (name: group: {
        ${group.uid} = {
          name_prefix = "${group.uid}-";
          description = "Security group for ASG in ${group.uid}";
          vpc_id = cfg.vpc.id;
          lifecycle = [{ create_before_destroy = true; }];
        };
      }) cfg.autoscalingGroups));

      resource.aws_vpc.${cfg.name} = {
        cidr_block = cfg.vpc.cidr;
        enable_dns_hostnames = true;
        tags = {
          Cluster = cfg.name;
          Name = cfg.name;
        };
      };

      resource.aws_network_interface = mapAttrs' (name: server:
        nameValuePair server.uid {
          subnet_id = server.subnet.id;
          security_groups = [ (id "aws_security_group.${cfg.name}-core") ];
          private_ips = [ server.privateIP ];
          tags = {
            Cluster = cfg.name;
            Name = server.name;
          };
        }) cfg.instances;

      resource.tls_private_key.ca = {
        algorithm = "RSA";
        ecdsa_curve = "P256";
        rsa_bits = "2048";
      };

      resource.tls_self_signed_cert.ca = {
        key_algorithm = var "tls_private_key.ca.algorithm";
        private_key_pem = var "tls_private_key.ca.private_key_pem";
        is_ca_certificate = true;

        allowed_uses =
          [ "cert_signing" "key_encipherment" "digital_signature" ];

        subject = {
          organization = cfg.certificate.organization;
          common_name = cfg.certificate.commonName;
        };

        validity_period_hours = 8760;
      };

      resource.tls_private_key.cert = resources.tls_private_key.ca;

      resource.tls_cert_request.cert = {
        key_algorithm = var "tls_private_key.cert.algorithm";
        private_key_pem = var "tls_private_key.cert.private_key_pem";

        dns_names = [
          "vault.service.consul"
          "consul.service.consul"
          "nomad.service.consul"
          "server.${cfg.region}.consul"
        ];
        ip_addresses = [ "127.0.0.1" ]
          ++ (mapAttrsToList (name: server: server.privateIP) cfg.instances);
        inherit (resources.tls_self_signed_cert.ca) subject;
      };

      resource.tls_locally_signed_cert.cert = {
        cert_request_pem = var "tls_cert_request.cert.cert_request_pem";

        ca_key_algorithm = var "tls_private_key.ca.algorithm";
        ca_private_key_pem = var "tls_private_key.ca.private_key_pem";
        ca_cert_pem = var "tls_self_signed_cert.ca.cert_pem";

        allowed_uses = [ "key_encipherment" "digital_signature" ];

        inherit (resources.tls_self_signed_cert.ca) validity_period_hours;
      };

      resource.aws_eip = mapAttrs' (name: server:
        nameValuePair server.uid {
          vpc = true;
          network_interface = id "aws_network_interface.${server.uid}";
          associate_with_private_ip = server.privateIP;
          tags = {
            Cluster = cfg.name;
            Name = server.name;
          };
          lifecycle = [{ create_before_destroy = true; }];
        }) cfg.instances;

      resource.aws_subnet = mapAttrs' (name: subnet:
        nameValuePair "${cfg.name}-${name}" {
          vpc_id = cfg.vpc.id;
          cidr_block = subnet.cidr;
          tags = {
            Cluster = cfg.name;
            Name = "${cfg.name}-${name}";
          };
          lifecycle = [{ create_before_destroy = true; }];
        }) cfg.vpc.subnets;

      resource.aws_internet_gateway.${cfg.name} = {
        vpc_id = cfg.vpc.id;
        tags = {
          Cluster = cfg.name;
          Name = cfg.name;
        };
        lifecycle = [{ create_before_destroy = true; }];
      };

      resource.aws_route_table.${cfg.name} = {
        vpc_id = cfg.vpc.id;
        route = [{
          cidr_block = "0.0.0.0/0";
          gateway_id = id "aws_internet_gateway.${cfg.name}";
          egress_only_gateway_id = null;
          instance_id = null;
          ipv6_cidr_block = null;
          nat_gateway_id = null;
          network_interface_id = null;
          transit_gateway_id = null;
          vpc_peering_connection_id = null;
        }];
        tags = {
          Cluster = cfg.name;
          Name = cfg.name;
        };
        lifecycle = [{ create_before_destroy = true; }];
      };

      resource.aws_route_table_association = mapAttrs' (name: subnet:
        nameValuePair "${cfg.name}-${name}-internet" {
          subnet_id = subnet.id;
          route_table_id = id "aws_route_table.${cfg.name}";
        }) cfg.vpc.subnets;

      data.aws_route53_zone.selected = mkIf cfg.route53 {
        provider = "aws.us_east_2";
        name = "${cfg.domain}.";
      };

      resource.aws_route53_record = mkIf cfg.route53 (let
        domains = (flatten (flip mapAttrsToList cfg.instances
          (instanceName: instance:
            forEach instance.route53.domains
            (subDomain: { ${subDomain} = instance.uid; }))));
      in flip mapAttrs' (zipAttrs domains) (subDomain: instanceUids:
        nameValuePair
        "${cfg.name}-${replaceStrings [ "." ] [ "_" ] subDomain}" {
          zone_id = id "data.aws_route53_zone.selected";
          name = "${subDomain}.${cfg.domain}";
          type = "A";
          ttl = "60";
          records = forEach instanceUids (uid: var "aws_eip.${uid}.public_ip");
        }));

      data.aws_availability_zones.available.state = "available";

      resource.aws_security_group_rule = let
        merge = foldl' recursiveUpdate { };

        mkRule = ({ prefix, rule, protocol }:
          let
            common = {
              type = rule.type;
              from_port = rule.from;
              to_port = rule.to;
              protocol = protocol;
              security_group_id = rule.securityGroupId;
            };

            from-self = (nameValuePair
              "${prefix}-${rule.type}-${protocol}-${rule.name}-self"
              (common // { self = true; }));

            from-cidr = (nameValuePair
              "${prefix}-${rule.type}-${protocol}-${rule.name}-cidr"
              (common // { cidr_blocks = rule.cidrs; }));

            from-ssgi = (nameValuePair
              "${prefix}-${rule.type}-${protocol}-${rule.name}-ssgi" (common
                // {
                  source_security_group_id = rule.sourceSecurityGroupId;
                }));

          in (optional (rule.self != false) from-self)
          ++ (optional (rule.cidrs != [ ]) from-cidr)
          ++ (optional (rule.sourceSecurityGroupId != null) from-ssgi));

        mapASG = _: group:
          merge (flip mapAttrsToList group.securityGroupRules (_: rule:
            listToAttrs (flatten (flip map rule.protocols (protocol:
              mkRule {
                prefix = group.uid;
                inherit rule protocol;
              })))));

        mapInstances = _: instance:
          merge (flip mapAttrsToList instance.securityGroupRules (_: rule:
            listToAttrs (flatten (flip map rule.protocols (protocol:
              mkRule {
                prefix = cfg.name;
                inherit rule protocol;
              })))));

        asgs = mapAttrsToList mapASG cfg.autoscalingGroups;
        instances = mapAttrsToList mapInstances cfg.instances;

      in merge (asgs ++ instances);

      # resource.null_resource = mapAttrs' (name: server:
      #   nameValuePair "${name}-local-provisioner" {
      #     provisioner.local-exec = {
      #       inherit (server.localProvisioner) interpreter command environment;
      #       working_dir = server.localProvisioner.workingDir;
      #     };
      #   }) cfg.instances;

    };
  };
}
