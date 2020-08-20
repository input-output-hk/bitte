{ self, config, pkgs, nodeName, ... }:
let
  # Needed to prevent infinite recursion.
  # pkgs = import self.inputs.nixpkgs {
  #   system = "x86_64-linux";
  #   overlays = [ self.overlay.x86_64-linux ];
  # };

  inherit (pkgs) lib terralib;
  inherit (lib) mkOption reverseList;
  inherit (lib.types)
    attrs submodule str attrsOf bool ints path enum port listof nullOr listOf
    oneOf list package;
  inherit (terralib) var id regions;

  kms2region = kms: builtins.elemAt (lib.splitString ":" kms) 3;

  merge = lib.foldl' lib.recursiveUpdate { };

  amis = let
    nixosAmis = import
      (self.inputs.nixpkgs + "/nixos/modules/virtualisation/ec2-amis.nix");
  in {
    nixos = lib.mapAttrs' (name: value: lib.nameValuePair name value.hvm-ebs)
      nixosAmis."20.03";
  };

  cfg = config.cluster;

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

      adminNames = mkOption {
        type = listOf str;
        default = [ ];
      };

      generateSSHKey = mkOption {
        type = bool;
        default = true;
      };

      region = mkOption {
        type = str;
        default = kms2region cfg.kms;
      };

      vpc = mkOption {
        type = vpcType cfg.name;
        default = {
          region = cfg.region;

          cidr = "172.16.0.0/16";

          subnets = {
            prv-1.cidr = "172.16.0.0/24";
            prv-2.cidr = "172.16.1.0/24";
            prv-3.cidr = "172.16.2.0/24";
          };
        };
      };

      certificate = mkOption {
        type = certificateType;
        default = { };
      };

      flakePath = mkOption {
        type = path;
        default = self.outPath;
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

      tfDataName = mkOption {
        type = str;
        default = var "data.aws_iam_role.${this.config.uid}.name";
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
          builtins.toJSON {
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

  initialVaultSecretsType = submodule ({ ... }@this: {
    options = {
      consul = mkOption { type = str; };

      nomad = mkOption { type = str; };
    };
  });

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

  vpcType = prefix:
    (submodule ({ ... }@this: {
      options = {
        name = mkOption {
          type = str;
          default = "${prefix}-${this.config.region}";
        };

        cidr = mkOption { type = str; };

        id = mkOption {
          type = str;
          default = id "data.aws_vpc.${this.config.name}";
        };

        region = mkOption { type = enum regions; };

        subnets = mkOption {
          type = attrsOf subnetType;
          default = { };
        };
      };
    }));

  subnetType = submodule ({ name, ... }@this: {
    options = {
      name = mkOption {
        type = str;
        default = name;
      };

      cidr = mkOption { type = str; };

      id = mkOption {
        type = str;
        default = id "aws_subnet.${this.config.name}";
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
            "--flake"
            "."
            "--attr"
            "${cfg.name}-${this.config.name}"
          ];
          rev = reverseList args;
          command = builtins.head rev;
          interpreter = reverseList (builtins.tail rev);
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

      securityGroupName = mkOption {
        type = str;
        default = "aws_security_group.${cfg.name}";
      };

      securityGroupId = mkOption {
        type = str;
        default = id this.config.securityGroupName;
      };

      securityGroupRules = mkOption {
        type = attrsOf (securityGroupRuleType {
          defaultSecurityGroupId = this.config.securityGroupId;
        });
        default = { };
      };

      initialVaultSecrets = mkOption {
        type = initialVaultSecretsType;
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

      uid = mkOption {
        type = str;
        default = "${cfg.name}-${this.config.name}";
      };

      modules = mkOption {
        type = listOf path;
        default = [ ];
      };

      ami = mkOption {
        type = str;
        default = amis.nixos.${this.config.region};
      };

      region = mkOption { type = str; };

      iam = mkOption { type = serverIamType this.config.name; };

      vpc = mkOption {
        type = vpcType this.config.uid;
        default = {
          region = this.config.region;

          cidr = "10.0.0.0/8";

          subnets = {
            "${this.config.name}-1".cidr = "10.0.0.0/18";
            "${this.config.name}-2".cidr = "10.0.1.0/18";
            "${this.config.name}-3".cidr = "10.0.2.0/18";
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

            systemd.services.install = {
              wantedBy = ["multi-user.target"];
              after = ["network-online.target"];
              path = with pkgs; [ config.system.build.nixos-rebuild nixFlakes awscli coreutils gnutar curl xz ];
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
                nix build ./source#nixosConfigurations.${cfg.name}-${this.config.name}.config.system.build.toplevel
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

      subnets = mkOption {
        type = listOf subnetType;
        default = builtins.attrValues this.config.vpc.subnets;
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

    instance = mkOption {
      type = nullOr attrs;
      default = cfg.instances.${nodeName} or null;
    };
  };
}
