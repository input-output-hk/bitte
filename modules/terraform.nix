{ self, config, pkgs, lib, nodeName, terralib, terranix, ... }:
let
  inherit (lib) mkOption reverseList;
  inherit (lib.types)
    attrs submodule str functionTo attrsOf bool ints path enum port listof
    nullOr listOf oneOf list package unspecified anything;
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
  userDataDefaultNixosConfigAsg = asg:
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
        "s3://${cfg.s3Bucket}/infra/secrets/${cfg.name}/${cfg.kms}/source/${asg}-source.tar.xz" \
        source.tar.xz || err_code=$?
      if test $err_code -eq 0
      then # automated provisioning
        mkdir -p source
        tar xvf source.tar.xz -C source
        nix build ./source#nixosConfigurations.${cfg.name}-${asg}.config.system.build.toplevel
        nixos-rebuild --flake ./source#${cfg.name}-${asg} switch
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

  clusterType = submodule (_: {
    options = {
      name = mkOption { type = str; };

      domain = mkOption { type = str; };

      secrets = mkOption { type = path; };

      terraformOrganization = mkOption { type = str; };

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
        default = coreAMIs."${cfg.region}"."${pkgs.system}" or (throw
          "Please make sure the NixOS core AMI is copied to ${cfg.region}");
      };

      iam = mkOption {
        type = clusterIamType;
        default = { };
      };

      kms = mkOption { type = str; };

      s3Bucket = mkOption { type = str; };

      s3Cache = mkOption {
        type = str;
        default =
          "s3://${cfg.s3Bucket}/infra/binary-cache/?region=${cfg.region}";
      };

      s3CachePubKey = mkOption { type = str; };

      adminNames = mkOption {
        type = listOf str;
        default = [ ];
      };

      adminGithubTeamNames = mkOption {
        type = listOf str;
        default = [ "devops" ];
      };

      developerGithubTeamNames = mkOption {
        type = listOf str;
        default = [ ];
      };

      developerGithubNames = mkOption {
        type = listOf str;
        default = [ ];
      };

      extraAcmeSANs = mkOption {
        type = listOf str;
        default = [ ];
        description = ''
          Extra subject alternative names to add to the default certs for the cluster.
        '';
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
          inherit (cfg) region;

          cidr = "172.16.0.0/16";

          subnets = {
            core-1.cidr = "172.16.0.0/24";
            core-2.cidr = "172.16.1.0/24";
            core-3.cidr = "172.16.2.0/24";
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

  iamRoleAssumePolicyType = submodule (this: {
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

  initialVaultSecretsType = submodule (this: {
    options = {
      consul = mkOption {
        type = str;
        default = builtins.trace "initialVaultSecrets is not used anymore!" "";
      };
      nomad = mkOption {
        type = str;
        default = builtins.trace "initialVaultSecrets is not used anymore!" "";
      };
    };
  });

  certificateType = submodule (this: {
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
    (submodule (this: {
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
        type = listOf anything;
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
        default = userDataDefaultNixosConfigCore;
      };

      localProvisioner = mkOption {
        type = localExecType;
        default = { protoCommand = localProvisionerDefaultCommand; };
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

      ebsOptimized = mkOption {
        type = nullOr bool;
        default = null;
      };
    };
  });

  localExecType = submodule {
    options = {
      protoCommand = mkOption { type = functionTo str; };

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

      node_class = mkOption { type = str; };

      modules = mkOption {
        type = listOf (oneOf [ path attrs ]);
        default = [ ];
      };

      ami = mkOption {
        type = str;
        default = clientAMIs."${this.config.region}"."${pkgs.system}" or (throw
          "Please make sure the NixOS ZFS Client AMI is copied to ${this.config.region}");
      };

      region = mkOption { type = str; };

      iam = mkOption { type = serverIamType this.config.name; };

      vpc = mkOption {
        type = vpcType this.config.uid;
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

      userData = mkOption {
        type = nullOr str;
        default = userDataDefaultNixosConfigAsg this.config.name;
      };

      localProvisioner = mkOption {
        type = localExecType;
        default = { protoCommand = localProvisionerDefaultCommand; };
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

      volumeSize = mkOption {
        type = ints.positive;
        default = 100;
      };

      volumeType = mkOption {
        type = str;
        default = "gp2";
      };

      tags = mkOption {
        type = attrsOf str;
        default = { };
      };

      associatePublicIP = mkOption {
        type = bool;
        default = true;
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
      default = cfg.instances."${nodeName}" or null;
    };

    asg = mkOption {
      type = nullOr attrs;
      default = cfg.autoscalingGroups."${nodeName}" or null;
    };

    tf = lib.mkOption {
      default = { };
      type = attrsOf (submodule ({ name, ... }@this: {
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
            for arg in "$@"
            do
              case "$arg" in
                *routing*|routing*|*routing)
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
            type = submodule {
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
            apply = v: pkgs.writeShellScriptBin "${name}-config" copy;
          };

          plan = lib.mkOption {
            type = lib.mkOptionType { name = "${name}-plan"; };
            apply = v:
              pkgs.writeShellScriptBin "${name}-plan" ''
                ${prepare}

                terraform plan -out ${name}.plan "$@"
              '';
          };

          apply = lib.mkOption {
            type = lib.mkOptionType { name = "${name}-apply"; };
            apply = v:
              pkgs.writeShellScriptBin "${name}-apply" ''
                ${prepare}

                terraform apply ${name}.plan "$@"
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
