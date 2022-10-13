{
  self,
  config,
  pkgs,
  lib,
  nodeName,
  terralib,
  terranix,
  bittelib,
  ...
} @ _protoArgs: let
  inherit (terralib) var id regions awsProviderFor amis;
  inherit (bittelib) net;

  kms2region = kms:
    if kms == null
    then null
    else builtins.elemAt (lib.splitString ":" kms) 3;

  relEncryptedFolder = let
    path = with config;
      if (cluster.infraType == "aws")
      then secrets.encryptedRoot
      else age.encryptedRoot;
  in
    lib.last (builtins.split "/nix/store/.{32}-" (toString path));

  merge = lib.foldl' lib.recursiveUpdate {};

  # without zfs
  coreAMIs = lib.pipe supportedRegions [
    # => us-east-1
    (map (region:
      lib.nameValuePair region {
        x86_64-linux = amis."21.05"."${region}".hvm-ebs;
      }))
    lib.listToAttrs
  ];

  # with zfs
  clientAMIs = {
    ca-central-1.x86_64-linux = "ami-0c00d841dac47a1fd";
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
  #
  # CAUTION: Without a special migration procedure, such as TF targeting,
  #          changing this user data will cause a forced destroy and
  #          re-create of all core nodes on the next TF core workspace plan/apply.
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

  # ${asg}-source.tar.xz is produced by a plan/apply
  # of the terraform client workspace
  userDataDefaultNixosConfigAsg = awsAsg: let
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
    cat <<'EOF' > /etc/finish-bootstrap.sh
    #!/bin/sh
    export NIX_CONFIG="${nixConf}"
    export PATH="/run/current-system/sw/bin:$PATH"
    set -exuo pipefail
    pushd /run/keys
    err_code=0
    aws s3 cp \
      "s3://${cfg.s3Bucket}/${var "aws_s3_bucket_object.${awsAsg}-flake.id"}" \
      source.tar.xz || err_code=$?
    if test $err_code -eq 0
    then # automated provisioning
      mkdir -p source
      tar xvf source.tar.xz -C source
      nix build ./source#nixosConfigurations.${cfg.name}-${awsAsg}.config.system.build.toplevel
      nixos-rebuild --flake ./source#${cfg.name}-${awsAsg} switch
    fi # manual provisioning
    EOF
    chmod +x /etc/finish-bootstrap.sh
    systemd-run --unit=nixos-init $_
  '';

  sshArgs = "-C -oConnectTimeout=5 -oUserKnownHostsFile=/dev/null -oNumberOfPasswordPrompts=0 -oServerAliveInterval=60 -oControlPersist=600 -oStrictHostKeyChecking=no -i ./secrets/ssh-${cfg.name}";
  ssh = "ssh ${sshArgs}";

  localProvisionerDefaultCommand = pkgs.writeShellApplication {
    name = "local-provisioner-default-command";
    runtimeInputs = with pkgs; [
      bitte
      git
      lsof
      mercurial
      nix
      openssh
      systemd
    ];

    text = let
      nixConf = ''
        experimental-features = nix-command flakes
      '';
      newKernelVersion = config.boot.kernelPackages.kernel.version;
    in ''
      ip="''${1?Must provide IP}"
      ssh_target="root@$ip"

      sleep 1

      echo
      echo Waiting for host to become ready ...
      until ${ssh} "$ssh_target" -- grep true /etc/ready &>/dev/null; do
        sleep 1
      done

      sleep 1

      export NIX_CONFIG="${nixConf}"

      echo
      echo Invoking deploy-rs on that host ...
      bitte deploy \
        --ssh-opts="-oUserKnownHostsFile=/dev/null" \
        --ssh-opts="-oNumberOfPasswordPrompts=0" \
        --ssh-opts="-oServerAliveInterval=60" \
        --ssh-opts="-oControlPersist=600" \
        --ssh-opts="-oStrictHostKeyChecking=no" \
        --skip-checks \
        --no-magic-rollback \
        --no-auto-rollback \
        "$ip"

      sleep 1

      echo
      echo Rebooting the host to load eventually newer kernels ...
      ${ssh} "$ssh_target" -- \
        "if [ \"$(cat /proc/sys/kernel/osrelease)\" != \"${newKernelVersion}\" ]; then \
        systemctl kexec \
        || (echo Rebooting instead ... && systemctl reboot) ; fi" \
      || true
    '';
  };

  localProvisionerBootstrapperCommand = pkgs.writeShellApplication {
    name = "bootstrap";
    runtimeInputs = with pkgs; [
      git
      jq
      openssh
      sops
    ];
    text = ''
      ip="''${1?Must provide IP}"
      ssh_target="root@$ip"

      if ! test -s ${relEncryptedFolder}/vault.enc.json; then
        echo
        echo Waiting for bootstrapping on core-1 to finish for vault /var/lib/vault/vault.enc.json ...
        while ! ${ssh} "$ssh_target" -- test -s /var/lib/vault/vault.enc.json &>/dev/null; do
          sleep 5
        done
        echo ... found /var/lib/vault/vault.enc.json
        secret="$(${ssh} "$ssh_target" -- cat /var/lib/vault/vault.enc.json)"
        echo "$secret" > ${relEncryptedFolder}/vault.enc.json
        git add ${relEncryptedFolder}/vault.enc.json
      fi
      if ! test -s ${relEncryptedFolder}/nomad.bootstrap.enc.json; then
        echo
        echo Waiting for bootstrapping on core-1 to finish for nomad /var/lib/nomad/bootstrap.token ...
        while ! ${ssh} "$ssh_target" -- test -s /var/lib/nomad/bootstrap.token &>/dev/null; do
          sleep 5
        done
        echo ... found /var/lib/nomad/bootstrap.token
        secret="$(${ssh} "$ssh_target" -- cat /var/lib/nomad/bootstrap.token)"
        echo "{}" | jq ".token = \"$secret\"" | sops --encrypt --input-type json --kms '${cfg.kms}' /dev/stdin > ${relEncryptedFolder}/nomad.bootstrap.enc.json
        git add ${relEncryptedFolder}/nomad.bootstrap.enc.json
      fi
    '';
  };

  cfg = config.cluster;

  clusterType = with lib.types;
    submodule (_: {
      imports = [
        bittelib.warningsModule
        (lib.mkRenamedOptionModule ["autoscalingGroups"]
          ["awsAutoScalingGroups"])
        (lib.mkRenamedOptionModule ["instances"] ["coreNodes"])
      ];
      options = {
        name = lib.mkOption {type = with lib.types; str;};

        domain = lib.mkOption {type = with lib.types; str;};

        secrets = lib.mkOption {type = with lib.types; path;};

        requiredInstanceTypes = lib.mkOption {
          internal = true;
          readOnly = true;
          type = with lib.types; listOf str;
          default = lib.pipe config.cluster.coreNodes [
            builtins.attrValues
            (map (lib.attrByPath ["instanceType"] null))
            lib.unique
          ];
        };

        requiredAsgInstanceTypes = lib.mkOption {
          internal = true;
          readOnly = true;
          type = with lib.types; listOf str;
          default = lib.pipe config.cluster.awsAutoScalingGroups [
            builtins.attrValues
            (map (lib.attrByPath ["instanceType"] null))
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
          default = {};
        };

        premSimNodes = lib.mkOption {
          type = with lib.types; attrsOf coreNodeType;
          default = {};
        };

        premNodes = lib.mkOption {
          type = with lib.types; attrsOf coreNodeType;
          default = {};
        };

        infraType = lib.mkOption {
          type = with lib.types; enum ["aws" "prem" "premSim"];
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
          default = {};
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
          default =
            coreAMIs."${cfg.region}"."${pkgs.system}"
            or (throw
              "Please make sure the NixOS core AMI is copied to ${cfg.region}");
        };

        iam = lib.mkOption {
          type = with lib.types; clusterIamType;
          default = {};
        };

        kms = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
        };

        s3Bucket = lib.mkOption {type = with lib.types; str;};

        s3Cache = lib.mkOption {
          type = with lib.types; nullOr str;
          default =
            if cfg.region == null
            then null
            else "s3://${cfg.s3Bucket}/infra/binary-cache/?region=${cfg.region}";
        };

        s3CachePubKey = lib.mkOption {type = with lib.types; str;};

        s3Tempo = lib.mkOption {type = with lib.types; str;};

        adminNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = [];
        };

        adminGithubTeamNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = ["devops"];
        };

        developerGithubTeamNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = [];
        };

        developerGithubNames = lib.mkOption {
          type = with lib.types; listOf str;
          default = [];
        };

        extraAcmeSANs = lib.mkOption {
          type = with lib.types; listOf str;
          default = [];
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
              (map (idx:
                lib.nameValuePair "core-${toString (idx + 1)}" {
                  cidr = net.cidr.subnet 8 idx cidr;
                  availabilityZone =
                    var
                    "element(module.instance_types_to_azs.availability_zones, ${toString idx})";
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
          default = {};
        };

        flakePath = lib.mkOption {
          type = with lib.types; path;
          default = self.outPath;
        };

        # For assistance with build machine state identification post-deployment
        # ex: see the common.nix profile
        sourceInfo = lib.mkOption {
          internal = true;
          type = with lib.types; attrsOf attrs;
          default =
            lib.mapAttrs (n: v: {
              inherit (v) lastModified lastModifiedDate narHash;

              rev =
                if v ? "rev"
                then v.rev
                else "dirty";
              shortRev =
                if v ? "shortRev"
                then v.shortRev
                else "dirty";

              # If "outPath" name is re-used then builtins.toJSON only converts outPath attrs and drops the rest.
              outPathSrc = v.outPath;
            })
            self.inputs;
        };

        vaultBackend = lib.mkOption {
          type = with lib.types; str;
          default = "https://vault.infra.aws.iohkdev.io";
          description = ''
            The vault URL to utilize to obtain remote VBK vault credentials.
          '';
        };

        # sic: reference to "Vault BacKend Backend"
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
          default = {};
        };
      };
    };

  iamRoleType = with lib.types;
    submodule ({name, ...} @ this: {
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
          default = {};
        };

        policies = lib.mkOption {
          type = with lib.types; attrsOf (iamRolePolicyType this.config.uid);
          default = {};
        };
      };
    });

  iamRolePolicyType = parentUid: (with lib.types;
    submodule ({name, ...} @ this: {
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
          type = with lib.types; enum ["Allow" "Deny"];
          default = "Allow";
        };

        actions = lib.mkOption {type = with lib.types; listOf str;};

        resources = lib.mkOption {type = with lib.types; listOf str;};

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
              Statement = [
                {
                  Effect = this.config.effect;
                  Principal.Service = this.config.principal.service;
                  Action = this.config.action;
                  Sid = "";
                }
              ];
            };
        };

        effect = lib.mkOption {
          type = with lib.types; enum ["Allow" "Deny"];
          default = "Allow";
        };

        action = lib.mkOption {type = with lib.types; str;};

        principal =
          lib.mkOption {type = with lib.types; iamRolePrincipalsType;};
      };
    });

  iamRolePrincipalsType = with lib.types;
    submodule {
      options = {service = lib.mkOption {type = with lib.types; str;};};
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

  securityGroupRuleType = {defaultSecurityGroupId}:
    with lib.types;
      submodule ({name, ...} @ this: {
        options = {
          name = lib.mkOption {
            type = with lib.types; str;
            default = name;
          };

          type = lib.mkOption {
            type = with lib.types; enum ["ingress" "egress"];
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
            type = with lib.types; listOf (enum ["tcp" "udp" "-1"]);
            default = ["tcp"];
          };

          cidrs = lib.mkOption {
            type = with lib.types; listOf str;
            default = [];
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

  vpcType = prefix: (with lib.types;
    submodule (this: {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = "${prefix}-${this.config.region}";
        };

        cidr = lib.mkOption {type = with lib.types; str;};

        id = lib.mkOption {
          type = with lib.types; str;
          default = id "data.aws_vpc.${this.config.name}";
        };

        region = lib.mkOption {type = with lib.types; enum regions;};

        subnets = lib.mkOption {
          type = with lib.types; attrsOf subnetType;
          default = {};
        };
      };
    }));

  subnetType = with lib.types;
    submodule ({name, ...} @ this: {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };

        availabilityZone = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
        };

        cidr = lib.mkOption {type = with lib.types; str;};

        id = lib.mkOption {
          type = with lib.types; str;
          default = id "aws_subnet.${this.config.name}";
        };
      };
    });

  ebsVolumeType = with lib.types;
    submodule ({name, ...} @ this: {
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
          role = lib.mkOption {type = with lib.types; iamRoleType;};

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

          role = lib.mkOption {type = with lib.types; iamRoleType;};

          path = lib.mkOption {
            type = with lib.types; str;
            default = "/";
          };
        };
      };

  coreNodeType = with lib.types;
    submodule ({name, ...} @ this: {
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
          type = with lib.types;
            listOf (mkOptionType {
              name = "submodule";
              inherit (submodule {}) check;
              merge = lib.options.mergeOneOption;
            });
          default = [];
        };

        node_class = lib.mkOption {
          type = with lib.types; str;
        };

        role = lib.mkOption {
          type = with lib.types; str;
          default =
            if lib.hasPrefix "core" name
            then "core"
            else if lib.hasPrefix "prem" name
            then "core"
            else if lib.hasPrefix "router" name
            then "router"
            else if lib.hasPrefix "routing" name
            then "router"
            else if lib.hasPrefix "monitor" name
            then "monitor"
            else if lib.hasPrefix "cache" name
            then "cache"
            else if lib.hasPrefix "storage" name
            then "storage"
            else if lib.hasPrefix "client" name
            then "client"
            else "default";
        };

        deployType = lib.mkOption {
          type = with lib.types; enum ["aws" "prem" "premSim"];
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
          default = {domains = [];};
          type = with lib.types;
            submodule {
              options = {
                domains = lib.mkOption {
                  type = with lib.types; listOf str;
                  default = [];
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
          default = {
            protoCommand = let
              drv = localProvisionerDefaultCommand;
            in "${drv}/bin/${drv.name}";

            bootstrapperCommand = let
              drv = localProvisionerBootstrapperCommand;
            in "${drv}/bin/${drv.name}";
          };
        };

        instanceType = lib.mkOption {type = with lib.types; str;};

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

        privateIP = lib.mkOption {type = with lib.types; str;};

        # flake = lib.mkOption { type = with lib.types; str; };

        datacenter = lib.mkOption {
          type = with lib.types; str;
          default =
            if this.config.deployType == "aws"
            then (kms2region cfg.kms)
            else "dc1";
        };

        subnet = lib.mkOption {
          type = with lib.types; subnetType;
          default = {};
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
          default = {};
        };

        initialVaultSecrets = lib.mkOption {
          type = with lib.types; initialVaultSecretsType;
          default = {};
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
        protoCommand = lib.mkOption {
          type = lib.types.str;
          description = "Provisioner command to be applied to all nodes";
        };

        bootstrapperCommand = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = ''
            Provisioner command to apply only to the first node, when applicable.
          '';
        };

        workingDir = lib.mkOption {
          type = with lib.types; nullOr path;
          default = null;
        };

        interpreter = lib.mkOption {
          type = with lib.types; nullOr (listOf str);
          default = ["${pkgs.bash}/bin/bash" "-c"];
        };

        environment = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = {};
        };
      };
    };

  awsAutoScalingGroupType = with lib.types;
    submodule ({name, ...} @ this: {
      options = {
        name = lib.mkOption {
          type = with lib.types; str;
          default = name;
        };

        uid = lib.mkOption {
          type = with lib.types; str;
          default = "${cfg.name}-${this.config.name}";
        };

        node_class = lib.mkOption {type = with lib.types; str;};

        role = lib.mkOption {
          type = with lib.types; str;
          default = "client";
        };

        modules = lib.mkOption {
          type = with lib.types; listOf (oneOf [path attrs (functionTo attrs)]);
          default = [];
        };

        deployType = lib.mkOption {
          type = with lib.types; enum ["aws" "prem" "premSim"];
          default = "aws";
        };

        primaryInterface = lib.mkOption {
          type = with lib.types; str;
          default = "ens5";
        };

        ami = lib.mkOption {
          type = with lib.types; str;
          default =
            clientAMIs."${this.config.region}"."${pkgs.system}"
            or (throw
              "Please make sure the NixOS ZFS Client AMI is copied to ${this.config.region}");
        };

        region = lib.mkOption {type = with lib.types; str;};

        iam =
          lib.mkOption {type = with lib.types; nodeIamType this.config.name;};

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
              (map (idx:
                lib.nameValuePair
                (lib.pipe atoz [
                  lib.stringToCharacters
                  (lib.flip builtins.elemAt idx)
                ]) {
                  cidr = net.cidr.subnet 2 idx cidr;
                  availabilityZone =
                    var
                    "element(module.instance_types_to_azs_${region}.availability_zones, ${toString idx})";
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
          default = {protoCommand = localProvisionerDefaultCommand;};
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
            oneOf [(enum [0]) (ints.between 604800 31536000)];
          default = 0;
        };

        instanceType = lib.mkOption {
          type = with lib.types; str;
          default = "t3a.medium";
        };

        volumeSize = lib.mkOption {
          type = with lib.types; ints.unsigned;
          default = 100;
        };

        volumeType = lib.mkOption {
          type = with lib.types; str;
          default = "gp2";
        };

        tags = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = {};
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
          default = {};
        };
      };
    });
in {
  imports = [
    (lib.mkRenamedOptionModule ["asg"] ["currentAwsAutoScalingGroup"])
    (lib.mkRenamedOptionModule ["instance"] ["currentCoreNode"])
  ];
  # propagate warnings so that they are exposed
  # config.warnings = config.cluster.warnings;
  options = {
    currentCoreNode = lib.mkOption {
      internal = true;
      type = with lib.types; nullOr attrs;
      default = let
        names =
          map builtins.attrNames [cfg.coreNodes cfg.premNodes cfg.premSimNodes];
        combinedNames = builtins.foldl' (s: v:
          s
          ++ (map (name:
            if (builtins.elem name s)
            then throw "Duplicate node name: ${name}"
            else name)
          v)) []
        names;
      in
        builtins.deepSeq combinedNames
        (cfg.coreNodes."${nodeName}"
          or cfg.premNodes."${nodeName}"
          or cfg.premSimNodes."${nodeName}"
          or null);
    };

    currentAwsAutoScalingGroup = lib.mkOption {
      internal = true;
      type = with lib.types; nullOr attrs;
      default = cfg.awsAutoScalingGroups."${nodeName}" or null;
    };

    cluster = lib.mkOption {
      type = with lib.types; clusterType;
      default = {};
    };

    tf = lib.mkOption {
      default = {};
      type = with lib.types;
        attrsOf (submodule (
          {
            config,
            name,
            ...
          }: {
            imports = [
              ((import ./terraform/tf-options.nix) {
                # _proto level args
                _protoConfig = _protoArgs.config;
                inherit (_protoArgs) pkgs terranix;
                inherit (pkgs) lib;

                # Submodule level args
                inherit config name;
              })
            ];
          }
        ));
    };
  };
}
