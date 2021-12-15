{ self, config, pkgs, nodeName, ... }:
let
  inherit (pkgs.terralib) var id regions awsProviderFor;

  kms2region = kms: builtins.elemAt (lib.splitString ":" kms) 3;

  merge = lib.foldl' lib.recursiveUpdate { };

  amis = let
    nixosAmis = import
      (self.inputs.nixpkgs + "/nixos/modules/virtualisation/ec2-amis.nix");
  in {
    nixos = lib.mapAttrs' (name: value: lib.nameValuePair name value.hvm-ebs)
      nixosAmis."20.03";
  };

  autoscalingAMIs = {
    us-east-2 = "ami-0492aa69cf46f79c3";
    eu-central-1 = "ami-0839f2c610f876d2d";
    eu-west-1 = "ami-0f765805e4520b54d";
    us-east-1 = "ami-02700dd542e3304cd";
  };

  vpcMap = lib.pipe [
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
    "sa-east-1"
    "us-east-1"
    "us-east-2"
    "us-west-1"
    "us-west-2"
  ] [ (lib.imap0 (i: v: lib.nameValuePair v i)) builtins.listToAttrs ];

  cfg = config.cluster;

  clusterType = with lib.types;
    submodule (_: {
      options = {
        name = lib.mkOption { type = with lib.types; str; };

        domain = lib.mkOption { type = with lib.types; str; };

        secrets = lib.mkOption { type = with lib.types; path; };

        terraformOrganization = lib.mkOption { type = with lib.types; str; };

        instances = lib.mkOption {
          type = with lib.types; attrsOf serverType;
          default = { };
        };

        autoscalingGroups = lib.mkOption {
          type = with lib.types; attrsOf autoscalingGroupType;
          default = { };
        };

        route53 = lib.mkOption {
          type = with lib.types; bool;
          default = true;
          description = "Enable route53 registrations";
        };

        ami = lib.mkOption {
          type = with lib.types; str;
          default = amis.nixos.${cfg.region};
        };

        iam = lib.mkOption {
          type = with lib.types; clusterIamType;
          default = { };
        };

        kms = lib.mkOption { type = with lib.types; str; };

        s3Bucket = lib.mkOption { type = with lib.types; str; };

        s3Cache = lib.mkOption {
          type = with lib.types; str;
          default =
            "s3://${cfg.s3Bucket}/infra/binary-cache/?region=${cfg.region}";
        };

        s3CachePubKey = lib.mkOption { type = with lib.types; str; };

        adminNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };

        adminGithubTeamNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ "devops" ];
        };

        developerGithubTeamNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };

        developerGithubNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };

        extraAcmeSANs = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
          description = ''
            Extra subject alternative names to add to the default certs for the cluster.

            NOTE: Use of this option requires a recent version of an ACME terraform
            provider, such as one of:

            https://github.com/getstackhead/terraform-provider-acme/releases/tag/v1.5.0-patched2
            https://github.com/vancluever/terraform-provider-acme/releases/tag/v2.4.0

            Specifically, the ACME provider version must be patched for this issue:

            https://github.com/vancluever/terraform-provider-acme/issues/154
          '';
        };

        generateSSHKey = lib.mkOption {
          type = with lib.types; bool;
          default = true;
        };

        region = lib.mkOption {
          type = with lib.types; str;
          default = kms2region cfg.kms;
        };

        vpc = lib.mkOption {
          type = with lib.types; vpcType cfg.name;
          default = {
            inherit (cfg) region;

            cidr = "172.16.0.0/16";

            subnets = {
              core-1.cidr = "172.16.0.0/24";
              core-2.cidr = "172.16.1.0/24";
              core-3.cidr = "172.16.2.0/24";
            };
          };
        };

        certificate = lib.mkOption {
          type = with lib.types; certificateType;
          default = { };
        };

        flakePath = lib.mkOption {
          type = with lib.types; path;
          default = self.outPath;
        };
      };
    });

  clusterIamType = with lib.types;
    submodule {
      options = {
        roles = lib.mkOption {
          type = with lib.types; attrsOf iamRoleType;
          default = { };
        };
      };
    };

  iamRoleType = with lib.types;
    submodule ({ name, ... }@this: {
      options = {
        id = lib.mkOption {
          type = with lib.types; str;
          default = id "aws_iam_role.${this.config.uid}";
        };

        uid = lib.mkOption {
          type = with lib.types; str;
          default = "${cfg.name}-${this.config.name}";
        };

        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };

        tfName = lib.mkOption {
          type = with lib.types; str;
          default = var "aws_iam_role.${this.config.uid}.name";
        };

        tfDataName = lib.mkOption {
          type = with lib.types; str;
          default = var "data.aws_iam_role.${this.config.uid}.name";
        };

        assumePolicy = lib.mkOption {
          type = with lib.types; iamRoleAssumePolicyType;
          default = { };
        };

        policies = lib.mkOption {
          type = with lib.types; attrsOf (iamRolePolicyType this.config.uid);
          default = { };
        };
      };
    });

  iamRolePolicyType = parentUid:
    (with lib.types;
      submodule ({ name, ... }@this: {
        options = {
          uid = lib.mkOption {
            type = with lib.types; str;
            default = "${parentUid}-${this.config.name}";
          };

          name = lib.mkOption {
            type = with lib.types; str;
            default = name;
          };

          effect = lib.mkOption {
            type = with lib.types; enum [ "Allow" "Deny" ];
            default = "Allow";
          };

          actions = lib.mkOption { type = with lib.types; listOf str; };

          resources = lib.mkOption { type = with lib.types; listOf str; };

          condition = lib.mkOption {
            type = with lib.types; nullOr (listOf attrs);
            default = null;
          };
        };
      }));

  iamRoleAssumePolicyType = with lib.types;
    submodule (this: {
      options = {
        tfJson = lib.mkOption {
          type = with lib.types; str;
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

        effect = lib.mkOption {
          type = with lib.types; enum [ "Allow" "Deny" ];
          default = "Allow";
        };

        action = lib.mkOption { type = with lib.types; str; };

        principal =
          lib.mkOption { type = with lib.types; iamRolePrincipalsType; };
      };
    });

  iamRolePrincipalsType = with lib.types;
    submodule {
      options = { service = lib.mkOption { type = with lib.types; str; }; };
    };

  initialVaultSecretsType = with lib.types;
    submodule (this: {
      options = {
        consul = lib.mkOption {
          type = with lib.types; str;
          default =
            builtins.trace "initialVaultSecrets is not used anymore!" "";
        };
        nomad = lib.mkOption {
          type = with lib.types; str;
          default =
            builtins.trace "initialVaultSecrets is not used anymore!" "";
        };
      };
    });

  certificateType = with lib.types;
    submodule (this: {
      options = {
        organization = lib.mkOption {
          type = with lib.types; str;
          default = "IOHK";
        };

        commonName = lib.mkOption {
          type = with lib.types; str;
          default = this.config.organization;
        };

        validityPeriodHours = lib.mkOption {
          type = with lib.types; ints.positive;
          default = 8760;
        };
      };
    });

  securityGroupRuleType = { defaultSecurityGroupId }:
    with lib.types;
    submodule ({ name, ... }@this: {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };

        type = lib.mkOption {
          type = with lib.types; enum [ "ingress" "egress" ];
          default = "ingress";
        };

        port = lib.mkOption {
          type = with lib.types; nullOr port;
          default = null;
        };

        from = lib.mkOption {
          type = with lib.types; port;
          default = this.config.port;
        };

        to = lib.mkOption {
          type = with lib.types; port;
          default = this.config.port;
        };

        protocols = lib.mkOption {
          type = with lib.types; listOf (enum [ "tcp" "udp" "-1" ]);
          default = [ "tcp" ];
        };

        cidrs = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
        };

        securityGroupId = lib.mkOption {
          type = with lib.types; str;
          default = defaultSecurityGroupId;
        };

        self = lib.mkOption {
          type = with lib.types; bool;
          default = false;
        };

        sourceSecurityGroupId = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
        };
      };
    });

  vpcType = prefix:
    (with lib.types;
      submodule (this: {
        options = {
          name = lib.mkOption {
            type = with lib.types; str;
            default = "${prefix}-${this.config.region}";
          };

          cidr = lib.mkOption { type = with lib.types; str; };

          id = lib.mkOption {
            type = with lib.types; str;
            default = id "data.aws_vpc.${this.config.name}";
          };

          region = lib.mkOption { type = with lib.types; enum regions; };

          subnets = lib.mkOption {
            type = with lib.types; attrsOf subnetType;
            default = { };
          };
        };
      }));

  subnetType = with lib.types;
    submodule ({ name, ... }@this: {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };

        cidr = lib.mkOption { type = with lib.types; str; };

        id = lib.mkOption {
          type = with lib.types; str;
          default = id "aws_subnet.${this.config.name}";
        };
      };
    });

  serverIamType = parentName:
    with lib.types;
    submodule {
      options = {
        role = lib.mkOption { type = with lib.types; iamRoleType; };

        instanceProfile = lib.mkOption {
          type = with lib.types; instanceProfileType parentName;
        };
      };
    };

  instanceProfileType = parentName:
    with lib.types;
    submodule {
      options = {
        tfName = lib.mkOption {
          type = with lib.types; str;
          readOnly = true;
          default =
            var "aws_iam_instance_profile.${cfg.name}-${parentName}.name";
        };

        tfArn = lib.mkOption {
          type = with lib.types; str;
          readOnly = true;
          default =
            var "aws_iam_instance_profile.${cfg.name}-${parentName}.arn";
        };

        role = lib.mkOption { type = with lib.types; iamRoleType; };

        path = lib.mkOption {
          type = with lib.types; str;
          default = "/";
        };
      };
    };

  serverType = with lib.types;
    submodule ({ name, ... }@this: {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };

        uid = lib.mkOption {
          type = with lib.types; str;
          default = "${cfg.name}-${name}";
        };

        enable = lib.mkOption {
          type = with lib.types; bool;
          default = true;
        };

        domain = lib.mkOption {
          type = with lib.types; str;
          default = "${this.config.name}.${cfg.domain}";
        };

        modules = lib.mkOption {
          type = with lib.types; listOf (oneOf [ path attrs ]);
          default = [ ];
        };

        ami = lib.mkOption {
          type = with lib.types; str;
          default = config.cluster.ami;
        };

        iam = lib.mkOption {
          type = with lib.types; serverIamType this.config.name;
          default = {
            role = cfg.iam.roles.core;
            instanceProfile.role = cfg.iam.roles.core;
          };
        };

        route53 = lib.mkOption {
          default = { domains = [ ]; };
          type = with lib.types;
            submodule {
              options = {
                domains = lib.mkOption {
                  type = with lib.types; listOf str;
                  default = [ ];
                };
              };
            };
        };

        userData = lib.mkOption {
          type = with lib.types; nullOr str;
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
                  "${cfg.s3Cache}"
                ];
                binaryCachePublicKeys = [
                  "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
                  "${cfg.s3CachePubKey}"
                ];
              };

              environment.etc.ready.text = "true";
            }
          '';
        };

        # Gotta do it this way since TF outputs aren't generated at this point and we need the IP.
        localProvisioner = lib.mkOption {
          type = with lib.types; localExecType;
          default = let
            ip = var "aws_eip.${this.config.uid}.public_ip";
            args = [
              "${pkgs.bitte}/bin/bitte"
              "provision"
              ip
              this.config.name # name
              cfg.name # cluster name
              "." # flake path
              "${cfg.name}-${this.config.name}" # flake attr
              cfg.s3Cache
            ];
            rev = reverseList args;
            command = builtins.head rev;
            interpreter = reverseList (builtins.tail rev);
          in { inherit command interpreter; };
        };

        postDeploy = lib.mkOption {
          type = with lib.types; localExecType;
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

        instanceType = lib.mkOption { type = with lib.types; str; };

        tags = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = {
            Cluster = cfg.name;
            Name = this.config.name;
            UID = this.config.uid;
            Consul = "server";
            Vault = "server";
            Nomad = "server";
          };
        };

        privateIP = lib.mkOption { type = with lib.types; str; };

        # flake = lib.mkOption { type = with lib.types; str; };

        subnet = lib.mkOption {
          type = with lib.types; subnetType;
          default = { };
        };

        volumeSize = lib.mkOption {
          type = with lib.types; ints.positive;
          default = 30;
        };

        securityGroupName = lib.mkOption {
          type = with lib.types; str;
          default = "aws_security_group.${cfg.name}";
        };

        securityGroupId = lib.mkOption {
          type = with lib.types; str;
          default = id this.config.securityGroupName;
        };

        securityGroupRules = lib.mkOption {
          type = with lib.types;
            attrsOf (securityGroupRuleType {
              defaultSecurityGroupId = this.config.securityGroupId;
            });
          default = { };
        };

        initialVaultSecrets = lib.mkOption {
          type = with lib.types; initialVaultSecretsType;
          default = { };
        };
      };
    });

  localExecType = with lib.types;
    submodule {
      options = {
        command = lib.mkOption { type = with lib.types; str; };

        workingDir = lib.mkOption {
          type = with lib.types; nullOr path;
          default = null;
        };

        interpreter = lib.mkOption {
          type = with lib.types; nullOr (listOf str);
          default = [ "${pkgs.bash}/bin/bash" "-c" ];
        };

        environment = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = { };
        };
      };
    };

  autoscalingGroupType = with lib.types;
    submodule ({ name, ... }@this: {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };

        uid = lib.mkOption {
          type = with lib.types; str;
          default = "${cfg.name}-${this.config.name}";
        };

        modules = lib.mkOption {
          type = with lib.types; listOf (oneOf [ path attrs ]);
          default = [ ];
        };

        ami = lib.mkOption {
          type = with lib.types; str;
          default = autoscalingAMIs.${this.config.region} or (throw
            "Please make sure the NixOS ZFS AMI is copied to ${this.config.region}");
        };

        region = lib.mkOption { type = with lib.types; str; };

        iam = lib.mkOption {
          type = with lib.types; serverIamType this.config.name;
        };

        vpc = lib.mkOption {
          type = with lib.types; vpcType this.config.uid;
          default = let base = toString (vpcMap.${this.config.region} * 4);
          in {
            inherit (this.config) region;

            cidr = "10.${base}.0.0/16";

            name = "${cfg.name}-${this.config.region}-asgs";
            subnets = {
              a.cidr = "10.${base}.0.0/18";
              b.cidr = "10.${base}.64.0/18";
              c.cidr = "10.${base}.128.0/18";
              # d.cidr = "10.${base}.192.0/18";
            };
          };
        };

        userData = lib.mkOption {
          type = with lib.types; nullOr str;
          default = ''
            # amazon-shell-init
            set -exuo pipefail

            /run/current-system/sw/bin/zpool online -e tank nvme0n1p3

            export CACHES="https://hydra.iohk.io https://cache.nixos.org ${cfg.s3Cache}"
            export CACHE_KEYS="hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ${cfg.s3CachePubKey}"
            pushd /run/keys
            aws s3 cp "s3://${cfg.s3Bucket}/infra/secrets/${cfg.name}/${cfg.kms}/source/source.tar.xz" source.tar.xz
            mkdir -p source
            tar xvf source.tar.xz -C source

            # TODO: add git to the AMI
            nix build nixpkgs#git -o git
            export PATH="$PATH:$PWD/git/bin"

            nix build ./source#nixosConfigurations.${cfg.name}-${this.config.name}.config.system.build.toplevel --option substituters "$CACHES" --option trusted-public-keys "$CACHE_KEYS"
            /run/current-system/sw/bin/nixos-rebuild --flake ./source#${cfg.name}-${this.config.name} boot --option substituters "$CACHES" --option trusted-public-keys "$CACHE_KEYS"
            /run/current-system/sw/bin/shutdown -r now
          '';
        };

        minSize = lib.mkOption {
          type = with lib.types; ints.unsigned;
          default = 0;
        };

        maxSize = lib.mkOption {
          type = with lib.types; ints.unsigned;
          default = 10;
        };

        desiredCapacity = lib.mkOption {
          type = with lib.types; ints.unsigned;
          default = 1;
        };

        maxInstanceLifetime = lib.mkOption {
          type = with lib.types;
            oneOf [ (enum [ 0 ]) (ints.between 604800 31536000) ];
          default = 0;
        };

        instanceType = lib.mkOption {
          type = with lib.types; str;
          default = "t3a.medium";
        };

        volumeSize = lib.mkOption {
          type = with lib.types; ints.positive;
          default = 100;
        };

        volumeType = lib.mkOption {
          type = with lib.types; str;
          default = "gp2";
        };

        tags = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = { };
        };

        associatePublicIP = lib.mkOption {
          type = with lib.types; bool;
          default = true;
        };

        subnets = lib.mkOption {
          type = with lib.types; listOf subnetType;
          default = builtins.attrValues this.config.vpc.subnets;
        };

        securityGroupId = lib.mkOption {
          type = with lib.types; str;
          default = id "aws_security_group.${this.config.uid}";
        };

        securityGroupRules = lib.mkOption {
          type = with lib.types;
            attrsOf (securityGroupRuleType {
              defaultSecurityGroupId = this.config.securityGroupId;
            });
          default = { };
        };
      };
    });
in {
  options = {
    cluster = lib.mkOption {
      type = with lib.types; clusterType;
      default = { };
    };

    instance = lib.mkOption {
      type = with lib.types; nullOr attrs;
      default = cfg.instances.${nodeName} or null;
    };

    asg = lib.mkOption {
      type = with lib.types; nullOr attrs;
      default = cfg.autoscalingGroups.${nodeName} or null;
    };

    tf = lib.mkOption {
      default = { };
      type = with lib.types;
        attrsOf (submodule ({ name, ... }@this: {
          options = let
            copy = ''
              export PATH="${
                lib.makeBinPath [ pkgs.coreutils pkgs.terraform-with-plugins ]
              }"
              set -euo pipefail

              rm -f config.tf.json
              cp "${this.config.output}" config.tf.json
              chmod u+rw config.tf.json
            '';

            prepare = ''
              ${copy}

              terraform workspace select "${name}" 1>&2
              terraform init 1>&2
            '';
          in {
            configuration =
              lib.mkOption { type = with lib.types; attrsOf unspecified; };

            output = lib.mkOption {
              type = lib.mkOptionType { name = "${name}_config.tf.json"; };
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

            config = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-config"; };
              apply = v: pkgs.writeShellScriptBin "${name}-config" copy;
            };

            plan = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-plan"; };
              apply = v:
                pkgs.writeShellScriptBin "${name}-plan" ''
                  ${prepare}

                  terraform plan -out ${name}.plan
                '';
            };

            apply = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-apply"; };
              apply = v:
                pkgs.writeShellScriptBin "${name}-apply" ''
                  ${prepare}

                  terraform apply ${name}.plan
                '';
            };

            terraform = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-apply"; };
              apply = v:
                pkgs.writeShellScriptBin "${name}-apply" ''
                  ${prepare}

                  terraform $@
                '';
            };
          };
        }));
    };
  };
}
