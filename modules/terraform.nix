{ self, config, pkgs, lib, nodeName, terralib, terranix, bittelib, ... }:
let
  inherit (terralib) var id regions awsProviderFor amis;
  inherit (bittelib) net;

  kms2region = kms: if kms == null then null else builtins.elemAt (lib.splitString ":" kms) 3;

  merge = lib.foldl' lib.recursiveUpdate { };

  sopsDecrypt = inputType: path:
    # NB: we can't work on store paths that don't yet exist before they are generated
    assert lib.assertMsg (builtins.isString path) "sopsDecrypt: path must be a string ${toString path}";
    "sops --decrypt --input-type ${inputType} ${path}";

  sopsEncrypt = inputType: outputType: path:
    assert lib.assertMsg (builtins.isString path) "sopsDecrypt: path must be a string ${toString path}";
    "sops --encrypt --kms ${toString cfg.kms} --input-type ${inputType} --output-type ${outputType} ${path}";

  isPrem = cfg.infraType == "prem";

  # encryptedRoot attrs must be declared at the config.* _proto level in the ops/world repos to be accessible here
  relEncryptedFolder = let
    extract = path: lib.last (builtins.split "/nix/store/.{32}-" (toString path));
  in if isPrem then extract config.age.encryptedRoot else extract config.secrets.encryptedRoot;

  # without zfs
  coreAMIs = lib.pipe supportedRegions [
    # => us-east-1
    (map (region: lib.nameValuePair region {
      x86_64-linux = amis."21.05"."${region}".hvm-ebs;
    }))
    lib.listToAttrs
  ];

  # with zfs
  clientAMIs = {
    eu-central-1.x86_64-linux = "ami-06924f74c403bc518";
    eu-west-1.x86_64-linux = "ami-0c38ecafe1b467389";
    us-east-1.x86_64-linux = "ami-0227fb009752240fa";
    us-east-2.x86_64-linux = "ami-04fc5c1fd5d3416ba";
    us-west-1.x86_64-linux = "ami-0bffd39e683c9fab2";
    us-west-2.x86_64-linux = "ami-09b83c344225d1128";
  };

  supportedRegions = [
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
  ];

  vpcMap = lib.pipe supportedRegions [
    (lib.imap0 (i: v: lib.nameValuePair v i))
    builtins.listToAttrs
  ];

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
          experimental-features = nix-command flakes
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
        experimental-features = nix-command flakes
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
          pkgs.nix
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

        requiredInstanceTypes = lib.mkOption {
          internal = true;
          readOnly = true;
          type = with lib.types; listOf str;
          default =
            lib.pipe config.cluster.coreNodes [
              builtins.attrValues
              (map (lib.attrByPath [ "instanceType" ] null))
              lib.unique
            ];
        };

        requiredAsgInstanceTypes = lib.mkOption {
          internal = true;
          readOnly = true;
          type = with lib.types; listOf str;
          default =
            lib.pipe config.cluster.awsAutoScalingGroups [
              builtins.attrValues
              (map (lib.attrByPath [ "instanceType" ] null))
              lib.unique
            ];
        };

        nodes = lib.mkOption {
          type = with lib.types; attrsOf coreNodeType;
          internal = true;
          default = cfg.coreNodes // cfg.premSimNodes // cfg.premNodes;
        };

        coreNodes = lib.mkOption {
          type = with lib.types; attrsOf coreNodeType;
          default = { };
        };

        premSimNodes = lib.mkOption {
          type = with lib.types; attrsOf coreNodeType;
          default = { };
        };

        premNodes = lib.mkOption {
          type = with lib.types; attrsOf coreNodeType;
          default = { };
        };

        infraType = lib.mkOption {
          type = with lib.types; enum [ "aws" "prem" "premSim" ];
          default = "aws";
          description = ''
            The cluster infrastructure deployment type.

            For an AWS cluster, "aws" should be declared.
            For an AWS plus premSim cluster, "aws" should be declared (see NB).
            For a premSim only cluster, "premSim" should be declared.
            For a prem only cluster, "prem" should be declared.

            The declared machine composition for a cluster should
            comprise machines of the declared cluster type:

              * type "aws" should declare coreNodes
              * type "prem" should declare premNodes
              * type "premSim" should declare premSimNodes

            NOTE: The use of AWS plus premSim deployment in the same
            cluster with mixed machine compoition of premNodes and
            premSimNodes is deprecated and will not be supported in
            the future.
          '';
        };

        awsAutoScalingGroups = lib.mkOption {
          type = with lib.types; attrsOf awsAutoScalingGroupType;
          default = { };
        };

        builder = lib.mkOption {
          type = types.str;
          default = "monitoring";
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

        kms = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
        };

        s3Bucket = lib.mkOption { type = with lib.types; str; };

        s3Cache = lib.mkOption {
          type = with lib.types; nullOr str;
          default = if cfg.region == null then null
            else "s3://${cfg.s3Bucket}/infra/binary-cache/?region=${cfg.region}";
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
          type = with lib.types; nullOr str;
          default = kms2region cfg.kms;
        };

        vpc = lib.mkOption {
          type = vpcType cfg.name;
          default = let
            cidr = "172.16.0.0/16";
          in {
            inherit cidr;
            inherit (cfg) region;

            subnets = lib.pipe 3 [
              (builtins.genList lib.id)
              (map (idx: lib.nameValuePair "core-${toString (idx+1)}" {
                cidr = net.cidr.subnet 8 idx cidr;
                availabilityZone =
                  var
                    "module.instance_types_to_azs.availability_zones[${toString idx}]";
              }))
              lib.listToAttrs
            ];
          };
        };

        premSimVpc = lib.mkOption {
          type = with lib.types; vpcType "${cfg.name}-premSim";
          default = let
            cidr = "10.255.0.0/16";
          in {
            inherit cidr;
            inherit (cfg) region;

            subnets = {
              premSim.cidr = net.cidr.subnet 8 0 cidr;
              premSim.availabilityZone =
                var
                  "module.instance_types_to_azs.availability_zones[0]";
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

        vaultBackend = lib.mkOption {
          type = with lib.types; str;
          default = "https://vault.infra.aws.iohkdev.io";
          description = ''
            The vault URL to utilize to obtain remote VBK vault credentials.
          '';
        };

        vbkBackend = lib.mkOption {
          type = with lib.types; str;
          default = lib.warn ''
            CAUTION: -- TF proto level cluster option vbkBackend default will change soon to:
            cluster.vbkBackend = "local";

            To migrate from remote state to local state usage, use:
            nix run .#clusters.$BITTE_CLUSTER.tf.<TF_WORKSPACE>.migrateLocal
          '' "https://vbk.infra.aws.iohkdev.io";
          description = ''
            The vault remote backend URL to utilize.
            Set this to "local" to utilize local state instead of remote state.
          '';
        };

        vbkBackendSkipCertVerification = lib.mkOption {
          type = with lib.types; bool;
          default = false;
          description = ''
            Whether to skip TLS verification.  Useful for debugging
            when signed certificates are not yet available in non
            prod environments.

            NOTE: The following local exports may also be required
            in conjunction with enabling this option, and are intended
            only for short term use in a testing only environment:

              export VAULT_SKIP_VERIFY=true
              export CONSUL_HTTP_SSL_VERIFY=false
              export NOMAD_SKIP_VERIFY=true
          '';
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

        availabilityZone = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
        };

        cidr = lib.mkOption { type = with lib.types; str; };

        id = lib.mkOption {
          type = with lib.types; str;
          default = id "aws_subnet.${this.config.name}";
        };
      };
    });

  ebsVolumeType = with lib.types;
    submodule ({ name, ... }@this: {
      options = {
        iops = lib.mkOption {
          type = with lib.types; int;
          default = 3000;
        };
        size = lib.mkOption {
          type = with lib.types; int;
          default = 500;
        };
        type = lib.mkOption {
          type = with lib.types; str;
          default = "gp3";
        };
        throughput = lib.mkOption {
          type = with lib.types; int;
          default = 125;
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
          # Required due to types.anything not being intended for arbitrary modules.
          # types.anything usage broken by:
          #   https://github.com/NixOS/nixpkgs/commit/48293bd6b6b791b9af745e9b7b94a6856e279fa0
          # Ref: https://github.com/NixOS/nixpkgs/issues/140879
          # TODO: use types.raw on next nixpkgs bump (>= 22.05)
          type = with lib.types; listOf (mkOptionType {
            name = "submodule";
            inherit (submodule { }) check;
            merge = lib.options.mergeOneOption;
          });
          default = [ ];
        };

        node_class = lib.mkOption {
          type = with lib.types; str;
        };

        role = lib.mkOption {
          type = with lib.types; str;
          default = if lib.hasPrefix "core" name then "core"
                    else if lib.hasPrefix "prem" name then "core"
                    else if lib.hasPrefix "router" name then "router"
                    else if lib.hasPrefix "routing" name then "router"
                    else if lib.hasPrefix "monitor" name then "monitor"
                    else if lib.hasPrefix "hydra" name then "hydra"
                    else if lib.hasPrefix "storage" name then "storage"
                    else if lib.hasPrefix "client" name then "client"
                    else "default";
        };

        deployType = lib.mkOption {
          type = with lib.types; enum [ "aws" "prem" "premSim" ];
          default = "aws";
        };

        primaryInterface = lib.mkOption {
          type = with lib.types; str;
          default = "ens5";
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

        ebsVolume = lib.mkOption {
          type = with lib.types; nullOr ebsVolumeType;
          default = null;
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

        role = lib.mkOption {
          type = with lib.types; str;
          default = "client";
        };

        modules = lib.mkOption {
          type = with lib.types; listOf (oneOf [ path attrs (functionTo attrs) ]);
          default = [ ];
        };

        deployType = lib.mkOption {
          type = with lib.types; enum [ "aws" "prem" "premSim" ];
          default = "aws";
        };

        primaryInterface = lib.mkOption {
          type = with lib.types; str;
          default = "ens5";
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
          type = vpcType this.config.uid;
          default = let
            inherit (this.config) region;
            base = toString (vpcMap.${this.config.region} * 4);
            cidr = "10.${base}.0.0/16";
            atoz = "abcdefghijklmnopqrstuvwxyz";
          in {
            inherit cidr region;

            name = "${cfg.name}-${this.config.region}-asgs";
            subnets = lib.pipe 3 [
              (builtins.genList lib.id)
              (map (idx: lib.nameValuePair
                (lib.pipe atoz [
                  lib.stringToCharacters
                  (lib.flip builtins.elemAt idx)
                ]) {
                  cidr = net.cidr.subnet 2 idx cidr;
                  availabilityZone =
                    var
                      "module.instance_types_to_azs_${region}.availability_zones[${toString idx}]";
                }))
              lib.listToAttrs
            ];
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
      default = let
        names =
          map builtins.attrNames [ cfg.coreNodes cfg.premNodes cfg.premSimNodes ];
        combinedNames = builtins.foldl' (s: v:
          s ++ (map (name:
            if (builtins.elem name s) then
              throw "Duplicate node name: ${name}"
            else
              name) v)) [ ] names;
      in builtins.deepSeq combinedNames
      (cfg.coreNodes."${nodeName}" or
      cfg.premNodes."${nodeName}" or
      cfg.premSimNodes."${nodeName}" or
      null);
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
            backend = "${cfg.vaultBackend}/v1";
            coreNode = if isPrem then "${cfg.name}-core-1" else "core-1";
            coreNodeCmd = if isPrem then "ssh" else "${pkgs.bitte}/bin/bitte ssh";
            encState = "${relEncryptedFolder}/tf/terraform-${name}.tfstate.enc";

            exportPath = ''
              export PATH="${
                with pkgs; lib.makeBinPath [
                  coreutils
                  curl
                  gitMinimal
                  jq
                  rage
                  sops
                  terraform-with-plugins
                ]
              }"
            '';

            # Generate declarative TF configuration and copy it to the top level repo dir
            copyTfCfg = ''
              set -euo pipefail
              ${exportPath}

              rm -f config.tf.json
              cp "${this.config.output}" config.tf.json
              chmod u+rw config.tf.json
            '';

            # Encrypt local state to the encrypted folder.
            # Use binary encryption instead of json for more compact representation
            # and to reduce information leakage via many unencrypted json keys.
            localStateEncrypt = ''
              if [ "${cfg.vbkBackend}" = "local" ]; then
                echo "Encrypting TF state changes to: ${encState}"
                if [ "${cfg.infraType}" = "prem" ]; then
                  rage -i secrets-prem/age-bootstrap -a -e "terraform-${name}.tfstate" > "${encState}"
                else
                  ${sopsEncrypt "binary" "binary" "terraform-${name}.tfstate"} > "${encState}"
                fi

                echo "Git adding state changes"
                git add ${if name == "hydrate-secrets" then "-f" else ""} "${encState}"

                echo
                warn "Please commit these TF state changes ASAP to avoid loss of state or state divergence!"
              fi
            '';

            # Local plaintext state should be uncommitted and cleaned up routinely
            # as some workspaces contain secrets, ex: hydrate-app
            localStateCleanup = ''
              if [ "${cfg.vbkBackend}" = "local" ]; then
                echo
                echo "Removing plaintext TF state files in the repo top level directory"
                echo "(alternatively, see the encrypted-committed TF state files as needed)"
                rm -vf terraform-${name}.tfstate
                rm -vf terraform-${name}.tfstate.backup
              fi
            '';

            migStartStatus = ''
              echo
              echo "Important environment variables"
              echo "  config.cluster.name              = ${cfg.name}"
              echo "  BITTE_CLUSTER env parameter      = $BITTE_CLUSTER"
              echo
              echo "Important migration variables:"
              echo "  infraType                        = ${cfg.infraType}"
              echo "  vaultBackend                     = ${cfg.vaultBackend}"
              echo "  vbkBackend                       = ${cfg.vbkBackend}"
              echo "  vbkBackendSkipCertVerification   = ${lib.boolToString cfg.vbkBackendSkipCertVerification}"
              echo "  script STATE_ARG                 = ''${STATE_ARG:-remote}"
              echo
              echo "Important path variables:"
              echo "  gitTopLevelDir                   = $TOP"
              echo "  currentWorkingDir                = $PWD"
              echo "  relEncryptedFolder               = ${relEncryptedFolder}"
              echo
            '';

            migCommonChecks = ''
              warn "PRE-MIGRATION CHECKS:"
              echo
              echo "Status:"

              # Ensure the TF workspace is available for the given infraType
              STATUS="$([ "${cfg.infraType}" = "prem" ] && [[ "${name}" =~ ^core$|^clients$|^prem-sim$ ]] && echo "FAIL" || echo "pass")"
              echo "  Infra type workspace check:      = $STATUS"
              gate "$STATUS" "The cluster infraType of \"prem\" cannot use the \"${name}\" TF workspace."

              # Ensure there is nothing strange with environment and cluster name mismatch that may cause unexpected issues
              STATUS="$([ "${cfg.name}" = "$BITTE_CLUSTER" ] && echo "pass" || echo "FAIL")"
              echo "  Cluster name check:              = $STATUS"
              gate "$STATUS" "The nix configured name of the cluster does not match the BITTE_CLUSTER env var."

              # Ensure the migration is being run from the top level of the git repo
              STATUS="$([ "$PWD" = "$TOP" ] && echo "pass" || echo "FAIL")"
              echo "  Current pwd check:               = $STATUS"
              gate "$STATUS" "The vbk migration to local state needs to be run from the top level dir of the git repo."

              # Ensure terraform config for workspace ${name} exists and has file size greater than zero bytes
              STATUS="$([ -s "config.tf.json" ] && echo "pass" || echo "FAIL")"
              echo "  Terraform config check:          = $STATUS"
              gate "$STATUS" "The terraform config.tf.json file for workspace ${name} does not exist or is zero bytes in size."

              # Ensure terraform config for workspace ${name} has expected remote backend state set properly
              STATUS="$([ "$(jq -e -r .terraform.backend.http.address < config.tf.json)" = "${cfg.vbkBackend}/state/${cfg.name}/${name}" ] && echo "pass" || echo "FAIL")"
              echo "  Terraform remote address check:  = $STATUS"
              gate "$STATUS" "The TF generated remote address does not match the expected declarative address."
            '';

            prepare = ''
              # shellcheck disable=SC2050
              set -euo pipefail
              ${exportPath}

              warn () {
                # Star header len matching the input str len
                printf '*%.0s' $(seq 1 ''${#1})

                echo -e "\n$1"

                # Star footer len matching the input str len
                printf '*%.0s' $(seq 1 ''${#1})
                echo
              }

              gate () {
                [ "$1" = "pass" ] || { echo; echo -e "FAIL: $2"; exit 1; }
              }

              TOP="$(git rev-parse --show-toplevel)"
              PWD="$(pwd)"

              # Ensure this TF operation is being run from the top level of the git repo
              STATUS="$([ "$PWD" = "$TOP" ] && echo "pass" || echo "FAIL")"
              MSG=(
                "The TF attrs need to be run from the top level directory of the repo:\n"
                " * Top level repo directory is:\n"
                "   $TOP\n"
                " * Current working directory is:\n"
                "   $PWD"
              )
              # shellcheck disable=SC2116
              gate "$STATUS" "$(echo "''${MSG[@]}")"

              if [ "${name}" = "hydrate-cluster" ]; then
                if [ "${cfg.infraType}" = "prem" ]; then
                  NOMAD_TOKEN="$(rage -i secrets-prem/age-bootstrap -d "${relEncryptedFolder}/nomad/nomad.bootstrap.enc.json" | jq -r '.token')"
                  VAULT_TOKEN="$(rage -i secrets-prem/age-bootstrap -d "${relEncryptedFolder}/vault/vault.enc.json" | jq -r '.root_token')"
                  CONSUL_HTTP_TOKEN="$(rage -i secrets-prem/age-bootstrap -d "${relEncryptedFolder}/consul/token-master.age")"
                else
                  NOMAD_TOKEN="$(${sopsDecrypt "json" "${relEncryptedFolder}/nomad.bootstrap.enc.json"} | jq -r '.token')"
                  VAULT_TOKEN="$(${sopsDecrypt "json" "${relEncryptedFolder}/vault.enc.json"} | jq -r '.root_token')"
                  CONSUL_HTTP_TOKEN="$(${sopsDecrypt "json" "${relEncryptedFolder}/consul-core.json"} | jq -r '.acl.tokens.master')"
                fi

                export NOMAD_TOKEN
                export VAULT_TOKEN
                export CONSUL_HTTP_TOKEN
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
                    echo
                    [[ ! "$REPLY" =~ ^[Yy]$ ]] && exit 0
                    ;;
                esac
              done

              # Generate and copy declarative TF state locally for TF to compare to
              ${copyTfCfg}

              if [ "${cfg.vbkBackend}" != "local" ]; then
                if [ -z "''${GITHUB_TOKEN:-}" ]; then
                  echo
                  echo -----------------------------------------------------
                  echo ERROR: env variable GITHUB_TOKEN is not set or empty.
                  echo Yet, it is required to authenticate before the
                  echo utilizing the cluster vault terraform backend.
                  echo -----------------------------------------------------
                  echo "Please 'export GITHUB_TOKEN=ghp_hhhhhhhh...' using"
                  echo your appropriate personal github access token.
                  echo -----------------------------------------------------
                  exit 1
                fi

                user="''${TF_HTTP_USERNAME:-TOKEN}"
                pass="''${TF_HTTP_PASSWORD:-$( \
                  curl -s -d "{\"token\": \"$GITHUB_TOKEN\"}" \
                  ${backend}/auth/github-terraform/login \
                  | jq -r '.auth.client_token' \
                )}"

                if [ -z "''${TF_HTTP_PASSWORD:-}" ]; then
                  echo
                  echo -----------------------------------------------------
                  echo TIP: you can avoid repetitive calls to the infra auth
                  echo api by exporting the following env variables as is.
                  echo
                  echo The current vault backend in use for TF is:
                  echo ${cfg.vaultBackend}
                  echo -----------------------------------------------------
                  echo "export TF_HTTP_USERNAME=\"$user\""
                  echo "export TF_HTTP_PASSWORD=\"$pass\""
                  echo -----------------------------------------------------
                fi

                export TF_HTTP_USERNAME="$user"
                export TF_HTTP_PASSWORD="$pass"

                echo "Using remote TF state for workspace \"${name}\"..."
                terraform init -reconfigure 1>&2
                STATE_ARG=""
              else
                echo "Using local TF state for workspace \"${name}\"..."

                # Ensure that local terraform state for workspace ${name} exists
                STATUS="$([ -f "${encState}" ] && echo "pass" || echo "FAIL")"
                MSG=(
                  "The nix _proto level cluster.vbkBackend option is set to \"local\", however\n"
                  " terraform local state for workspace \"${name}\" does not exist at:\n\n"
                  "   ${encState}\n\n"
                  "If all TF workspaces are not yet migrated to local, then:\n"
                  " * Set the cluster.vbkBackend option back to the existing remote backend\n"
                  " * Run the following against each TF workspace that is not yet migrated to local state:\n"
                  "   nix run .#clusters.$BITTE_CLUSTER.tf.<TF_WORKSPACE>.migrateLocal\n"
                  " * Finally, set the cluster.vbkBackend option to \"local\""
                )
                # shellcheck disable=SC2116
                gate "$STATUS" "$(echo "''${MSG[@]}")"


                # Ensure there is no unknown terraform state in the current directory
                for STATE in terraform*.tfstate terraform*.tfstate.backup; do
                  [ -f "$STATE" ] && {
                    echo
                    echo "Leftover terraform local state exists in the top level repo directory at:"
                    echo "  ''${TOP}/$STATE"
                    echo
                    echo "This may be due to a failed terraform command."
                    echo "Diff may be used to compare leftover state against encrypted-committed state."
                    echo
                    echo "When all expected state is confirmed to reside in the encrypted-committed state,"
                    echo "then delete this $STATE file and try again."
                    echo
                    echo "A diff example command for sops encrypted-commited state is:"
                    echo
                    echo "  icdiff $STATE \\"
                    if [ "${cfg.infraType}" = "prem" ]; then
                      echo "  <(rage -i secrets-prem/age-bootstrap -d \"${encState}\")"
                    else
                      echo "  <(sops -d \"${encState}\")"
                    fi
                    echo
                    echo "Leftover plaintext TF state should not be committed and should be removed as"
                    echo "soon as possible since it may contain secrets."
                    exit 1
                  }
                done

                # Check if uncommitted changes to local state already exist
                [ -z "$(git status --porcelain=2 "${encState}")" ] || {
                  echo
                  warn "WARNING: Uncommitted TF state changes already exist for workspace \"${name}\" at encrypted file:"
                  echo
                  echo "  ${encState}"
                  echo
                  echo "Any new changes to TF state will be automatically git added to changes that already exist."
                  read -p "Do you want to continue this operation? [y/n] " -n 1 -r
                  echo
                  [[ ! "$REPLY" =~ ^[Yy]$ ]] && exit 0
                }

                # Removing existing .terraform/terraform.tfstate avoids a backend reconfigure failure
                # or a remote state migration pull which has already been done via the migrateLocal attr.
                #
                # Our deployments do not currently store anything but backend
                # or local state information in this hidden directory tfstate file.
                #
                # Ref: https://stackoverflow.com/questions/70636974/side-effects-of-removing-terraform-folder
                rm -vf .terraform/terraform.tfstate
                if [ "${cfg.infraType}" = "prem" ]; then
                  rage -i secrets-prem/age-bootstrap -d "${encState}" > terraform-${name}.tfstate
                else
                  ${sopsDecrypt "binary" "${encState}"} > terraform-${name}.tfstate
                fi

                terraform init -reconfigure 1>&2
                STATE_ARG="-state=terraform-${name}.tfstate"
              fi
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
              apply = v: pkgs.writeBashBinChecked "${name}-config" copyTfCfg;
            };

            plan = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-plan"; };
              apply = v:
                pkgs.writeBashBinChecked "${name}-plan" ''
                  ${prepare}

                  terraform plan ''${STATE_ARG:-} -out ${name}.plan "$@" && {
                    ${localStateCleanup}
                  }
                '';
            };

            apply = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-apply"; };
              apply = v:
                pkgs.writeBashBinChecked "${name}-apply" ''
                  ${prepare}

                  terraform apply ''${STATE_ARG:-} ${name}.plan "$@" && {
                    ${localStateEncrypt}
                    ${localStateCleanup}
                  }
                '';
            };

            terraform = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-custom"; };
              apply = v:
                pkgs.writeBashBinChecked "${name}-custom" ''
                  ${prepare}

                  [ "${cfg.vbkBackend}" = "local" ] && {
                    warn "Nix custom terraform command usage note for local state:"
                    echo
                    echo "Depending on the terraform command you are running,"
                    echo "the state file argument may need to be provided:"
                    echo
                    echo "  $STATE_ARG"
                    echo
                    echo "********************************************************"
                    echo
                  }

                  terraform "$@" && {
                    ${localStateEncrypt}
                    ${localStateCleanup}
                  }
                '';
            };

            migrateLocal = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-migrateLocal"; };
              apply = v:
                pkgs.writeBashBinChecked "${name}-migrateLocal" ''
                  ${prepare}

                  warn "TERRAFORM VBK MIGRATION TO *** LOCAL STATE *** FOR ${name}:"

                  ${migStartStatus}
                  ${migCommonChecks}

                  # Ensure the vbk status is not already local
                  STATUS="$([ "${cfg.vbkBackend}" != "local" ] && echo "pass" || echo "FAIL")"
                  echo "  Terraform backend check:         = $STATUS"
                  MSG=(
                    "The nix _proto level cluster.vbkBackend option is already set to \"local\".\n"
                    "If all TF workspaces are not yet migrated to local, then:\n"
                    " * Set the cluster.vbkBackend option back to the existing remote backend\n"
                    " * Run the following against each TF workspace that is not yet migrated to local state:\n"
                    "   nix run .#clusters.$BITTE_CLUSTER.tf.<TF_WORKSPACE>.migrateLocal\n"
                    " * Finally, set the cluster.vbkBackend option to \"local\"\n"
                  )
                  # shellcheck disable=SC2116
                  gate "$STATUS" "$(echo "''${MSG[@]}")"

                  # Ensure that local terraform state for workspace ${name} does not already exist
                  STATUS="$([ ! -f "${encState}" ] && echo "pass" || echo "FAIL")"
                  echo "  Terraform local state presence:  = $STATUS"
                  gate "$STATUS" "Terraform local state for workspace \"${name}\" appears to already exist at: ${encState}"
                  echo

                  warn "STARTING MIGRATION FOR TF WORKSPACE ${name}"
                  echo
                  echo "Status:"

                  # Ensure the target state encrypted directory path exists
                  echo -n "  Creating target state path       "
                  mkdir -p "${relEncryptedFolder}/tf"
                  echo "...done"

                  # Set up a tmp work dir
                  echo -n "  Create a tmp work dir            "
                  TMPDIR="$(mktemp -d -t tf-${name}-migrate-local-XXXXXX)"
                  trap 'rm -rf -- "$TMPDIR"' EXIT
                  echo "...done"

                  # Pull remote state for ${name} to the tmp work dir
                  echo -n "  Fetching remote state            "
                  terraform state pull > "$TMPDIR/terraform-${name}.tfstate"
                  echo "...done"

                  # Encrypt the plaintext TF state file
                  echo -n "  Encrypting locally               "
                  if [ "${cfg.infraType}" = "prem" ]; then
                    rage -i secrets-prem/age-bootstrap -a -e "$TMPDIR/terraform-${name}.tfstate" > "${encState}"
                  else
                    ${sopsEncrypt "binary" "binary" "\"$TMPDIR/terraform-${name}.tfstate\""} > "${encState}"
                  fi
                  echo "...done"
                  echo

                  # Git add encrypted state
                  # In the case of hydrate-secrets, force add to avoid git exclusion in some ops/world repos based on the filename containing the word secret
                  echo -n "  Adding encrypted state to git    "
                  git add ${if name == "hydrate-secrets" then "-f" else ""} "${encState}"
                  echo "...done"
                  echo

                  warn "FINISHED MIGRATION TO LOCAL FOR TF WORKSPACE ${name}"
                  echo
                  echo "  * The encrypted local state file is found at:"
                  echo "    ${encState}"
                  echo
                  echo "  * Decrypt and review with:"
                  if [ "${cfg.infraType}" = "prem" ]; then
                    echo "    rage -i secrets-prem/age-bootstrap -d \"${encState}\""
                  else
                    echo "    sops -d \"${encState}\""
                    echo
                    echo "NOTE: binary sops encryption is used on the TF state files both for more compact representation"
                    echo "      and to avoid unencrypted keys from contributing to an information attack vector."
                  fi
                  echo "  * Once the local state is confirmed working as expected, the corresponding remote state no longer in use may be deleted:"
                  echo "    ${cfg.vbkBackend}/state/${cfg.name}/${name}"
                  echo
                '';
            };

            migrateRemote = lib.mkOption {
              type = lib.mkOptionType { name = "${name}-migrateRemote"; };
              apply = v:
                pkgs.writeBashBinChecked "${name}-migrateRemote" ''
                  ${prepare}

                  warn "TERRAFORM VBK MIGRATION TO *** REMOTE STATE *** FOR ${name}:"

                  ${migStartStatus}
                  ${migCommonChecks}

                  # Ensure the vbk status is already remote as the target vbkBackend remote parameter is required
                  STATUS="$([ "${cfg.vbkBackend}" != "local" ] && echo "pass" || echo "FAIL")"
                  echo "  Terraform backend check:         = $STATUS"
                  MSG=(
                    "The nix _proto level cluster.vbkBackend option is already set to \"local\".\n"
                    "If all TF workspaces are not yet migrated to remote, then:\n"
                    " * Set the cluster.vbkBackend option to the target migration remote backend, example:\n"
                    "   https://vbk.\$FQDN\n"
                    " * Run the following against each TF workspace that is not yet migrated to remote state:\n"
                    "   nix run .#clusters.$BITTE_CLUSTER.tf.<TF_WORKSPACE>.migrateRemote\n"
                    " * Remove the TF local state which is no longer in use at your convienence"
                  )
                  # shellcheck disable=SC2116
                  gate "$STATUS" "$(echo "''${MSG[@]}")"

                  # Ensure that local terraform state for workspace ${name} does already exist
                  STATUS="$([ -f "${encState}" ] && echo "pass" || echo "FAIL")"
                  echo "  Terraform local state presence:  = $STATUS"
                  gate "$STATUS" "Terraform local state for workspace \"${name}\" appears to not already exist at: ${encState}"

                  # Ensure that remote terraform state for workspace ${name} does not already exist
                  STATUS="$(terraform state list &> /dev/null && echo "FAIL" || echo "pass")"
                  echo "  Terraform remote state presence: = $STATUS"
                  MSG=(
                    "Terraform remote state for workspace \"${name}\" appears to already exist at backend vbk path: ${cfg.vbkBackend}/state/${cfg.name}/${name}\n"
                    " * Pushing local TF state to remote will reset the lineage and serial number of the remote state by default\n"
                    " * If this local state still needs to be pushed to this remote:\n"
                    "   * Ensure remote state is not needed\n"
                    "   * Back it up if desired\n"
                    "   * Clear this particular vbk remote state path key\n"
                    "   * Try again\n"
                    " * This will ensure lineage conflicts, serial state conflicts, and otherwise unexpected state data loss are not encountered"
                  )
                  # shellcheck disable=SC2116
                  gate "$STATUS" "$(echo "''${MSG[@]}")"
                  echo

                  warn "STARTING MIGRATION FOR TF WORKSPACE ${name}"
                  echo
                  echo "Status:"

                  # Set up a tmp work dir
                  echo -n "  Create a tmp work dir            "
                  TMPDIR="$(mktemp -d -t tf-${name}-migrate-remote-XXXXXX)"
                  trap 'rm -rf -- "$TMPDIR"' EXIT
                  echo "...done"

                  # Decrypt the pre-existing TF state file
                  echo -n "  Decrypting locally               "
                  if [ "${cfg.infraType}" = "prem" ]; then
                    rage -i secrets-prem/age-bootstrap -d "${encState}" > "$TMPDIR/terraform-${name}.tfstate"
                  else
                    ${sopsDecrypt "binary" "${encState}"} > "$TMPDIR/terraform-${name}.tfstate"
                  fi
                  echo "...done"
                  echo

                  # Copy the config with generated remote
                  echo -n "  Setting up config.tf.json        "
                  cp config.tf.json "$TMPDIR/config.tf.json"
                  echo "...done"
                  echo

                  # Initialize a new TF state dir with remote backend
                  echo "  Initializing remote config       "
                  echo
                  pushd "$TMPDIR"
                  terraform init -reconfigure
                  echo "...done"
                  echo

                  # Push the local state to the remote
                  echo "  Pushing local state to remote    "
                  echo
                  terraform state push terraform-${name}.tfstate
                  echo "...done"
                  echo
                  popd
                  echo

                  warn "FINISHED MIGRATION TO REMOTE FOR TF WORKSPACE ${name}"
                  echo
                  echo "  * The new remote state file is found at vbk path:"
                  echo "    ${cfg.vbkBackend}/state/${cfg.name}/${name}"
                  echo
                  echo "  * The associated encrypted local state no longer in use may now be deleted:"
                  echo "    ${encState}"
                  echo
                '';
            };
          };
        }));
    };
  };
}
