{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib) sops2kms sops2region cidrsOf;
  inherit (builtins) readFile replaceStrings;
  inherit (config.cluster.vpc) subnets;
  inherit (pkgs.terralib) var id pp;
  global = "0.0.0.0/0";

  nixosAmis =
    import (self.inputs.nixpkgs + "/nixos/modules/virtualisation/ec2-amis.nix");

  amis = {
    nixos = lib.mapAttrs' (name: value: lib.nameValuePair name value.hvm-ebs)
      nixosAmis."20.03";
  };

  availableKms = {
    atala.us-east-2 =
      "arn:aws:kms:us-east-2:895947072537:key/683261a5-cb8a-4f28-a507-bae96551ee5d";
    atala.eu-central-1 =
      "arn:aws:kms:eu-central-1:895947072537:key/214e1694-7f2e-4a00-9b23-08872b79c9c3";
    atala-testnet.us-east-2 =
      "arn:aws:kms:us-east-2:276730534310:key/2a265813-cabb-4ab7-aff6-0715134d5660";
    atala-testnet.eu-central-1 =
      "arn:aws:kms:eu-central-1:276730534310:key/5193b747-7449-40f6-976a-67d91257abdb";
  };

  # TODO: derive needed security groups from networking.firewall?
  securityGroupRules = {
    internet = {
      type = "egress";
      port = 0;
      protocols = [ "-1" ];
      cidrs = [ global ];
    };

    internal = {
      type = "ingress";
      port = 0;
      protocols = [ "-1" ];
      cidrs = cidrsOf subnets;
    };

    ssh = {
      port = 22;
      cidrs = [ global ];
    };

    http = {
      port = 80;
      cidrs = [ global ];
    };

    https = {
      port = 443;
      cidrs = [ global ];
    };

    consul-serf-lan = {
      port = 8301;
      protocols = [ "tcp" "udp" ];
      self = true;
      cidrs = cidrsOf subnets;
    };

    consul-grpc = {
      port = 8502;
      protocols = [ "tcp" "udp" ];
      cidrs = cidrsOf subnets;
    };

    nomad-serf-lan = {
      port = 4648;
      protocols = [ "tcp" "udp" ];
      cidrs = cidrsOf subnets;
    };

    nomad-rpc = {
      port = 4647;
      cidrs = cidrsOf subnets;
    };

    nomad-http = {
      port = 4646;
      cidrs = cidrsOf subnets;
    };
  };
in {
  cluster = {
    name = "atala-testnet";

    # TODO: this should really go into the servers and support more than one...
    region = "eu-central-1";

    # TODO: figure out better KMS strategy
    kms = availableKms.atala.eu-central-1;

    domain = "atala-testnet.aws.iohkdev.io";

    route53 = true;

    certificate.organization = "IOHK";

    generateSSHKey = true;

    vpc = {
      cidr = "10.0.0.0/16";

      subnets = {
        prv-1.cidr = "10.0.0.0/19";
        prv-2.cidr = "10.0.32.0/19";
        prv-3.cidr = "10.0.64.0/19";
      };
    };

    autoscalingGroups = (lib.flip lib.mapAttrs' {
      # iPXE is only supported on non-Nitro instances, that means we won't
      # get the latest and greates until they fix that...
      # All currently supported instance families with their smallest type:

      # "m4.large" = 1;
      # "t2.large" = 0;
      # "m3.large" = 0;
      # "c4.xlarge" = 0;
      # "d2.xlarge" = 0;
      # "r3.large" = 0;
      # "c3.large" = 0;

      # Use NixOS AMI for now
      "t3a.medium" = 1;
    } (instanceType: desiredCapacity:
      let
        saneName = "clients-${lib.replaceStrings [ "." ] [ "-" ] instanceType}";
      in lib.nameValuePair saneName {
        inherit desiredCapacity instanceType;
        associatePublicIP = true;
        maxInstanceLifetime = 604800;
        ami = amis.nixos.${config.cluster.region};
        iam.role = config.cluster.iam.roles.client;
        iam.instanceProfile.role = config.cluster.iam.roles.client;

        subnets = [ subnets.prv-1 subnets.prv-2 subnets.prv-3 ];

        modules = [ ../../../profiles/client.nix ];

        userData = ''
          ### https://nixos.org/channels/nixpkgs-unstable nixos
          { pkgs, config, ... }: {
            imports = [ <nixpkgs/nixos/modules/virtualisation/amazon-image.nix> ];

            nix = {
              package = pkgs.nixFlakes;
              extraOptions = '''
                show-trace = true
                experimental-features = nix-command flakes ca-references recursive-nix
              ''';
              systemFeatures = [ "recursive-nix" "nixos-test" ];
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
              path = with pkgs; [ config.system.build.nixos-rebuild coreutils gnutar curl xz ];
              restartIfChanged = false;
              unitConfig.X-StopOnRemoval = false;
              serviceConfig.Type = "oneshot";
              serviceConfig.Restart = "on-failure";
              serviceConfig.RestartSec = "30s";
              script = '''
                set -exuo pipefail
                pushd /run/keys
                curl -o source.tar.xz http://ipxe.${config.cluster.domain}/source.tar.xz
                mkdir -p source
                tar xvf source.tar.xz -C source
                nixos-rebuild --flake ./source#${config.cluster.name}-${saneName} boot
                booted="$(readlink /run/booted-system/{initrd,kernel,kernel-modules})"
                built="$(readlink /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules})"
                if [ "$booted" = "$built" ]; then
                  nixos-rebuild --flake ./source#${config.cluster.name}-${saneName} switch
                else
                  /run/current-system/sw/bin/shutdown -r now
                fi
              ''';
            };
          }
        '';

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      }));

    instances = {
      core-1 = {
        instanceType = "t3a.medium";
        privateIP = "10.0.0.10";
        subnet = subnets.prv-1;
        iam.role = config.cluster.iam.roles.core;
        iam.instanceProfile.role = config.cluster.iam.roles.core;

        modules =
          [ ../../../profiles/core.nix ../../../profiles/bootstrapper.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh http https;
        };
      };

      core-2 = {
        instanceType = "t3a.medium";
        privateIP = "10.0.32.10";
        subnet = subnets.prv-2;
        iam.role = config.cluster.iam.roles.core;
        iam.instanceProfile.role = config.cluster.iam.roles.core;

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "t3a.medium";
        privateIP = "10.0.64.10";
        subnet = subnets.prv-3;
        iam.role = config.cluster.iam.roles.core;
        iam.instanceProfile.role = config.cluster.iam.roles.core;

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };
    };

    iam = {
      roles = {
        client = {
          assumePolicy = {
            effect = "Allow";
            action = "sts:AssumeRole";
            principal.service = "ec2.amazonaws.com";
          };

          policies = {
            ssm = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [
                "ec2:ReportInstanceStatus"
                "ec2messages:AcknowledgeMessage"
                "ec2messages:DeleteMessage"
                "ec2messages:FailMessage"
                "ec2messages:GetEndpoint"
                "ec2messages:GetMessages"
                "ec2messages:SendReply"
                "ssmmessages:CreateControlChannel"
                "ssmmessages:CreateDataChannel"
                "ssmmessages:OpenControlChannel"
                "ssmmessages:OpenDataChannel"
                "ssm:DescribeAssociation"
                "ssm:GetDeployablePatchSnapshotForInstance"
                "ssm:GetDocument"
                "ssm:DescribeDocument"
                "ssm:GetManifest"
                "ssm:GetParameter"
                "ssm:GetParameters"
                "ssm:ListAssociations"
                "ssm:ListInstanceAssociations"
                "ssm:PutInventory"
                "ssm:PutComplianceItems"
                "ssm:PutConfigurePackageResult"
                "ssm:UpdateAssociationStatus"
                "ssm:UpdateInstanceAssociationStatus"
                "ssm:UpdateInstanceInformation"
              ];
            };

            ecr = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [
                "ecr:GetAuthorizationToken"
                "ecr:BatchCheckLayerAvailability"
                "ecr:GetDownloadUrlForLayer"
                "ecr:GetRepositoryPolicy"
                "ecr:DescribeRepositories"
                "ecr:ListImages"
                "ecr:DescribeImages"
                "ecr:BatchGetImage"
                "ecr:GetLifecyclePolicy"
                "ecr:GetLifecyclePolicyPreview"
                "ecr:ListTagsForResource"
                "ecr:DescribeImageScanFindings"
              ];
            };

            nomad = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [ "autoscaling:SetInstanceHealth" ];
            };

            consul = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [
                "ec2:DescribeInstances"
                "ec2:DescribeTags"
                "autoscaling:DescribeAutoScalingGroups"
              ];
            };

            vault = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [
                "ec2:DescribeInstances"
                "iam:GetInstanceProfile"
                "iam:GetUser"
                "iam:GetRole"
                "logs:CreateLogStream"
                "logs:PutLogEvents"
              ];
            };

            kms = {
              effect = "Allow";
              resources = [ config.cluster.kms ];
              actions = [ "kms:Encrypt" "kms:Decrypt" "kms:DescribeKey" ];
            };
          };
        };

        core = {
          assumePolicy = {
            effect = "Allow";
            action = "sts:AssumeRole";
            principal.service = "ec2.amazonaws.com";
          };

          policies = {
            kms = {
              effect = "Allow";
              resources = [ config.cluster.kms ];
              actions = [ "kms:Encrypt" "kms:Decrypt" "kms:DescribeKey" ];
            };

            assumeRole = {
              effect = "Allow";
              resources = [
                config.cluster.instances.core-1.iam.instanceProfile.tfArn
                config.cluster.instances.core-2.iam.instanceProfile.tfArn
                config.cluster.instances.core-3.iam.instanceProfile.tfArn
              ];
              actions = [ "sts:AssumeRole" ];
            };

            ssm = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [
                "ec2:ReportInstanceStatus"
                "ec2messages:AcknowledgeMessage"
                "ec2messages:DeleteMessage"
                "ec2messages:FailMessage"
                "ec2messages:GetEndpoint"
                "ec2messages:GetMessages"
                "ec2messages:SendReply"
                "ssmmessages:CreateControlChannel"
                "ssmmessages:CreateDataChannel"
                "ssmmessages:OpenControlChannel"
                "ssmmessages:OpenDataChannel"
                "ssm:DescribeAssociation"
                "ssm:GetDeployablePatchSnapshotForInstance"
                "ssm:GetDocument"
                "ssm:DescribeDocument"
                "ssm:GetManifest"
                "ssm:GetParameter"
                "ssm:GetParameters"
                "ssm:ListAssociations"
                "ssm:ListInstanceAssociations"
                "ssm:PutInventory"
                "ssm:PutComplianceItems"
                "ssm:PutConfigurePackageResult"
                "ssm:UpdateAssociationStatus"
                "ssm:UpdateInstanceAssociationStatus"
                "ssm:UpdateInstanceInformation"
              ];
            };

            nomad = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [ "autoscaling:SetInstanceHealth" ];
            };

            consul = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [
                "ec2:DescribeInstances"
                "ec2:DescribeTags"
                "autoscaling:DescribeAutoScalingGroups"
              ];
            };

            vault = {
              effect = "Allow";
              resources = [ "*" ];
              actions = [
                "ec2:DescribeInstances"
                "iam:GetInstanceProfile"
                "iam:GetUser"
                "iam:GetRole"
                "logs:CreateLogStream"
                "logs:PutLogEvents"
              ];
            };
          };
        };
      };
    };
  };
}
