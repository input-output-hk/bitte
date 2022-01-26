{ self, config, pkgs, lib, nodeName, terralib, terranix, bittelib, ... }:
let
  inherit (terralib) var id regions awsProviderFor;

  kms2region = kms: builtins.elemAt (lib.splitString ":" kms) 3;

  merge = lib.foldl' lib.recursiveUpdate { };

  # without zfs
  coreAMIs = {
    eu-central-1.x86_64-linux = "ami-0961cad26b3399fce";
    eu-west-1.x86_64-linux = "ami-010d1407e12e86a68";
    us-east-1.x86_64-linux = "ami-0641447e25cba1b93";
    us-east-2.x86_64-linux = "ami-00bc9ae8a038a7ccd";
    us-west-1.x86_64-linux = "ami-037994350972840c1";
    us-west-2.x86_64-linux = "ami-0fe2b3e2649511a18";
  };

  # with zfs
  clientAMIs = {
    eu-central-1.x86_64-linux = "ami-06924f74c403bc518";
    eu-west-1.x86_64-linux = "ami-0c38ecafe1b467389";
    us-east-1.x86_64-linux = "ami-0227fb009752240fa";
    us-east-2.x86_64-linux = "ami-04fc5c1fd5d3416ba";
    us-west-1.x86_64-linux = "ami-0bffd39e683c9fab2";
    us-west-2.x86_64-linux = "ami-09b83c344225d1128";
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

  # This user data only injects the cache and nix3 config so that
  # deploy-rs can take it from there (efficiently)
  userDataDefaultNixosConfigCore = ''
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

  # ${asg}-source.tar.xz is produced by s3-upload-flake.service
  # of one of the latest successfully provisioned member of this
  # auto scaling group
  userDataDefaultNixosConfigAsg = awsAsg:
    let
      nixConf = ''
        extra-substituters = ${cfg.s3Cache}
        extra-trusted-public-keys = ${cfg.s3CachePubKey}
      '';
      # amazon-init detects the shebang as a signal
      # but does not actually execve the script:
      # interpreter fixed to pkgs.runtimeShell.
      # For available packages, see or modify /profiles/slim.nix
    in ''
      #!
      export NIX_CONFIG="${nixConf}"
      export PATH="/run/current-system/sw/bin:$PATH"
      set -exuo pipefail
      pushd /run/keys
      err_code=0
      aws s3 cp \
        "s3://${cfg.s3Bucket}/infra/secrets/${cfg.name}/${cfg.kms}/source/${awsAsg}-source.tar.xz" \
        source.tar.xz || err_code=$?
      if test $err_code -eq 0
      then # automated provisioning
        mkdir -p source
        tar xvf source.tar.xz -C source
        nix build ./source#nixosConfigurations.${cfg.name}-${awsAsg}.config.system.build.toplevel
        nixos-rebuild --flake ./source#${cfg.name}-${awsAsg} switch
      fi # manual provisioning
    '';

  localProvisionerDefaultCommand = ip:
    let
      nixConf = ''
        experimental-features = nix-command flakes ca-references
      '';
      newKernelVersion = config.boot.kernelPackages.kernel.version;
    in ''
      set -euo pipefail

      echo
      echo Waiting for ssh to come up on port 22 ...
      while [ -z "$(
        ${pkgs.socat}/bin/socat \
          -T2 stdout \
          tcp:${ip}:22,connect-timeout=2,readbytes=1 \
          2>/dev/null
      )" ]
      do
          printf " ."
          sleep 5
      done

      sleep 1

      echo
      echo Waiting for host to become ready ...
      ${pkgs.openssh}/bin/ssh -C \
        -oUserKnownHostsFile=/dev/null \
        -oNumberOfPasswordPrompts=0 \
        -oServerAliveInterval=60 \
        -oControlPersist=600 \
        -oStrictHostKeyChecking=accept-new \
        -i ./secrets/ssh-${cfg.name} \
        root@${ip} \
        "until grep true /etc/ready &>/dev/null; do sleep 1; done 2>/dev/null"

      sleep 1

      export NIX_CONFIG="${nixConf}"
      export PATH="${
        lib.makeBinPath [
          pkgs.openssh
          pkgs.nixUnstable
          pkgs.git
          pkgs.mercurial
          pkgs.lsof
        ]
      }:$PATH"

      echo
      echo Invoking deploy-rs on that host ...
      ${pkgs.bitte}/bin/bitte deploy \
        --ssh-opts="-oUserKnownHostsFile=/dev/null" \
        --ssh-opts="-oNumberOfPasswordPrompts=0" \
        --ssh-opts="-oServerAliveInterval=60" \
        --ssh-opts="-oControlPersist=600" \
        --ssh-opts="-oStrictHostKeyChecking=no" \
        --skip-checks \
        --no-magic-rollback \
        --no-auto-rollback \
        ${ip}

      sleep 1

      echo
      echo Rebooting the host to load eventually newer kernels ...
      timeout 5 ${pkgs.openssh}/bin/ssh -C \
        -oUserKnownHostsFile=/dev/null \
        -oNumberOfPasswordPrompts=0 \
        -oServerAliveInterval=60 \
        -oControlPersist=600 \
        -oStrictHostKeyChecking=accept-new \
        -i ./secrets/ssh-${cfg.name} \
        root@${ip} \
        "if [ \"$(cat /proc/sys/kernel/osrelease)\" != \"${newKernelVersion}\" ]; then \
         ${pkgs.systemd}/bin/systemctl kexec \
         || (echo Rebooting instead ... && ${pkgs.systemd}/bin/systemctl reboot) ; fi" \
      || true
    '';

  cfg = config.cluster;

  clusterType = with lib.types;
    submodule (_: {
      imports = [
        bittelib.warningsModule
        (lib.mkRenamedOptionModule [ "autoscalingGroups" ]
          [ "awsAutoScalingGroups" ])
        (lib.mkRenamedOptionModule [ "instances" ] [ "coreNodes" ])
      ];
      options = {
        name = lib.mkOption { type = with lib.types; str; };

        domain = lib.mkOption { type = with lib.types; str; };

        secrets = lib.mkOption { type = with lib.types; path; };

        terraformOrganization = lib.mkOption { type = with lib.types; str; };

        coreNodes = lib.mkOption {
          type = with lib.types; attrsOf coreNodeType;
          default = { };
        };

        premSimNodes = lib.mkOption {
          type = with lib.types; attrsOf coreNodeType;
          default = { };
        };

        awsAutoScalingGroups = lib.mkOption {
          type = with lib.types; attrsOf awsAutoScalingGroupType;
          default = { };
        };

        route53 = lib.mkOption {
          type = with lib.types; bool;
          default = true;
          description = "Enable route53 registrations";
        };

        ami = lib.mkOption {
          type = with lib.types; str;
          default = coreAMIs."${cfg.region}"."${pkgs.system}" or (throw
            "Please make sure the NixOS core AMI is copied to ${cfg.region}");
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

        premSimVpc = lib.mkOption {
          type = with lib.types; vpcType "${cfg.name}-premSim";
          default = {
            inherit (cfg) region;

            cidr = "10.255.0.0/16";

            subnets = {
              premSim.cidr = "10.255.0.0/24";
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

  nodeIamType = parentName:
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

  coreNodeType = with lib.types;
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
          type = with lib.types; listOf anything;
          default = [ ];
        };

        node_class = lib.mkOption {
          type = with lib.types; str;
        };

        deployType = lib.mkOption {
          type = with lib.types; enum [ "aws" "prem" "premSim" ];
          default = "aws";
        };

        ami = lib.mkOption {
          type = with lib.types; str;
          default = config.cluster.ami;
        };

        iam = lib.mkOption {
          type = with lib.types; nodeIamType this.config.name;
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
          default = userDataDefaultNixosConfigCore;
        };

        localProvisioner = lib.mkOption {
          type = with lib.types; localExecType;
          default = { protoCommand = localProvisionerDefaultCommand; };
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

        datacenter = lib.mkOption {
          type = with lib.types; str;
          default = if this.config.deployType == "aws" then (kms2region cfg.kms) else "dc1";
        };

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

        ebsOptimized = lib.mkOption {
          type = with lib.types; nullOr bool;
          default = null;
        };
      };
    });

  localExecType = with lib.types;
    submodule {
      options = {
        protoCommand = lib.mkOption { type = with lib.types; functionTo str; };

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

  awsAutoScalingGroupType = with lib.types;
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

        node_class = lib.mkOption { type = with lib.types; str; };

        modules = lib.mkOption {
          type = with lib.types; listOf (oneOf [ path attrs ]);
          default = [ ];
        };

        deployType = lib.mkOption {
          type = with lib.types; enum [ "aws" "prem" "premSim" ];
          default = "aws";
        };

        ami = lib.mkOption {
          type = with lib.types; str;
          default =
            clientAMIs."${this.config.region}"."${pkgs.system}" or (throw
              "Please make sure the NixOS ZFS Client AMI is copied to ${this.config.region}");
        };

        region = lib.mkOption { type = with lib.types; str; };

        iam =
          lib.mkOption { type = with lib.types; nodeIamType this.config.name; };

        vpc = lib.mkOption {
          type = with lib.types; vpcType this.config.uid;
          default = let base = toString (vpcMap."${this.config.region}" * 4);
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
          default = userDataDefaultNixosConfigAsg this.config.name;
        };

        localProvisioner = lib.mkOption {
          type = with lib.types; localExecType;
          default = { protoCommand = localProvisionerDefaultCommand; };
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
  imports = [
    (lib.mkRenamedOptionModule [ "asg" ] [ "currentAwsAutoScalingGroup" ])
    (lib.mkRenamedOptionModule [ "instance" ] [ "currentCoreNode" ])
  ];
  # propagate warnings so that they are exposed
  # config.warnings = config.cluster.warnings;
  options = {

    currentCoreNode = lib.mkOption {
      internal = true;
      type = with lib.types; nullOr attrs;
      default = cfg.coreNodes."${nodeName}" or cfg.premSimNodes."${nodeName}" or null;
    };

    currentAwsAutoScalingGroup = lib.mkOption {
      internal = true;
      type = with lib.types; nullOr attrs;
      default = cfg.awsAutoScalingGroups."${nodeName}" or null;
    };

    cluster = lib.mkOption {
      type = with lib.types; clusterType;
      default = { };
    };

    tf = lib.mkOption {
      default = { };
      type = with lib.types;
        attrsOf (submodule ({ name, ... }@this: {
          options = let
            backend = "https://vault.infra.aws.iohkdev.io/v1";
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
              # shellcheck disable=SC2050
              if [ "${name}" == "hydrate-cluster" ]; then
                echo
                echo -----------------------------------------------------
                echo Fetching nomad bootstrap token for hydrate-cluster.
                echo This is a standard requirement since nomad does not
                echo implement fine-grained ACL. Hence, for hydrate-cluster
                echo a management token is required. The boostrap token is
                echo such a management token.
                echo Fetching from 'core-1', the presumed bootstrapper ...
                echo -----------------------------------------------------
                declare NOMAD_TOKEN
                NOMAD_TOKEN="$(${pkgs.bitte}/bin/bitte ssh core-1 cat /var/lib/nomad/bootstrap.token)"
                export NOMAD_TOKEN
              fi

              for arg in "$@"
              do
                case "$arg" in
                  *routing*)
                    echo
                    echo -----------------------------------------------------
                    echo CAUTION: It appears that you are indulging on a
                    echo terraform operation specifically involving routing.
                    echo Are you redeploying routing?
                    echo -----------------------------------------------------
                    echo You MUST know that a redeploy of routing will
                    echo necesarily re-trigger the bootstrapping of the ACME
                    echo service.
                    echo -----------------------------------------------------
                    echo You MUST also know that LetsEncrypt enforces a non-
                    echo recoverable rate limit of 5 generations per week.
                    echo That means: only ever redeploy routing max 5 times
                    echo per week on a rolling basis. Switch to the LetsEncrypt
                    echo staging envirenment if you plan on deploying routing
                    echo more often!
                    echo -----------------------------------------------------
                    echo
                    read -p "Do you want to continue this operation? [y/n] " -n 1 -r
                    if [[ ! "$REPLY" =~ ^[Yy]$ ]]
                    then
                      exit
                    fi
                    ;;
                esac
              done

              ${copy}
              if [ -z "''${GITHUB_TOKEN:-}" ]; then
                echo
                echo -----------------------------------------------------
                echo ERROR: env variable GITHUB_TOKEN is not set or empty.
                echo Yet, it is required to authenticate before the
                echo infra cluster vault terraform backend.
                echo -----------------------------------------------------
                echo "Please 'export GITHUB_TOKEN=ghp_hhhhhhhh...' using"
                echo your appropriate personal github access token.
                echo -----------------------------------------------------
                exit 1
              fi

              user="''${TF_HTTP_USERNAME:-TOKEN}"
              pass="''${TF_HTTP_PASSWORD:-$( \
                ${pkgs.curl}/bin/curl -s -d "{\"token\": \"$GITHUB_TOKEN\"}" \
                ${backend}/auth/github-terraform/login \
                | ${pkgs.jq}/bin/jq -r '.auth.client_token' \
              )}"

              if [ -z "''${TF_HTTP_PASSWORD:-}" ]; then
                echo
                echo -----------------------------------------------------
                echo TIP: you can avoid repetitive calls to the infra auth
                echo api by exporting the following env variables as is:
                echo -----------------------------------------------------
                echo "export TF_HTTP_USERNAME=\"$user\""
                echo "export TF_HTTP_PASSWORD=\"$pass\""
                echo -----------------------------------------------------
              fi

              export TF_HTTP_USERNAME="$user"
              export TF_HTTP_PASSWORD="$pass"

              terraform init -reconfigure 1>&2
            '';
          in {
            configuration = lib.mkOption {
              type = with lib.types;
                submodule {
                  imports = [ (terranix + "/core/terraform-options.nix") ];
                };
            };

            output = lib.mkOption {
              type = lib.mkOptionType { name = "${name}_config.tf.json"; };
              apply = v:
                terranix.lib.terranixConfiguration {
                  inherit pkgs;
                  modules = [ this.config.configuration ];
                  strip_nulls = false;
                };
            };

            config = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-config"; };
              apply = v: pkgs.writeBashBinChecked "${name}-config" copy;
            };

            plan = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-plan"; };
              apply = v:
                pkgs.writeBashBinChecked "${name}-plan" ''
                  ${prepare}

                  terraform plan -out ${name}.plan "$@"
                '';
            };

            apply = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-apply"; };
              apply = v:
                pkgs.writeBashBinChecked "${name}-apply" ''
                  ${prepare}

                  terraform apply ${name}.plan "$@"
                '';
            };

            terraform = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-apply"; };
              apply = v:
                pkgs.writeBashBinChecked "${name}-apply" ''
                  ${prepare}

                  terraform "$@"
                '';
            };
          };
        }));
    };
  };
}
