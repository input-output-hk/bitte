{ self, lib, pkgs, config, terralib, ... }:
let
  inherit (terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute mkAttachment mkStorage;
  inherit (config.cluster) infraType vbkBackend vbkBackendSkipCertVerification;

  merge = lib.foldl' lib.recursiveUpdate { };
  tags = { Cluster = config.cluster.name; };

  infraTypeCheck = if builtins.elem infraType [ "aws" "premSim" ] then true else (throw ''
    To utilize the core TF attr, the cluster config parameter `infraType`
    must either "aws" or "premSim".
  '');
  sopsEncrypt =
    "${pkgs.sops}/bin/sops --encrypt --input-type json --kms '${config.cluster.kms}' /dev/stdin";

  sopsDecrypt = path:
    # NB: we can't work on store paths that don't yet exist before they are generated
    assert lib.assertMsg (builtins.isString path) "sopsDecrypt: path must be a string ${toString path}";
    "${pkgs.sops}/bin/sops --decrypt --input-type json ${path}";

  relEncryptedFolder = lib.last (builtins.split "-" (toString config.secrets.encryptedRoot));

in {
  tf.core.configuration = lib.mkIf infraTypeCheck {
    terraform.backend = lib.mkIf (vbkBackend != "local") {
      http = let
        vbk =
          "${vbkBackend}/state/${config.cluster.name}/core";
      in {
        address = vbk;
        lock_address = vbk;
        unlock_address = vbk;
        skip_cert_verification = vbkBackendSkipCertVerification;
      };
    };

    terraform.required_providers = pkgs.terraform-provider-versions;

    provider = {
      acme = { server_url = "https://acme-v02.api.letsencrypt.org/directory"; };

      aws = [{ inherit (config.cluster) region; }] ++ (lib.forEach regions
        (region: {
          inherit region;
          alias = awsProviderNameFor region;
        }));
    };

    module.instance_types_to_azs = {
      source = "${./modules/instance-types-to-azs}";
      instance_types = config.cluster.requiredInstanceTypes;
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

    resource.aws_subnet = lib.flip lib.mapAttrs' config.cluster.vpc.subnets
      (name: subnet:
        lib.nameValuePair subnet.name {
          provider = awsProviderFor config.cluster.vpc.region;
          vpc_id = id "aws_vpc.core";
          cidr_block = subnet.cidr;
          # This indirectly consumes "module.instance_types_to_azs"
          availability_zone = subnet.availabilityZone;

          lifecycle = [{ create_before_destroy = true; }];

          tags = {
            Cluster = config.cluster.name;
            Name = subnet.name;
          };
        });

    resource.aws_route_table_association = lib.mapAttrs' (name: subnet:
      lib.nameValuePair "${config.cluster.name}-${name}-internet" {
        subnet_id = subnet.id;
        route_table_id = id "aws_route_table.${config.cluster.name}";
      }) config.cluster.vpc.subnets;

    # ---------------------------------------------------------------
    # DNS
    # ---------------------------------------------------------------

    data.aws_route53_zone.selected = lib.mkIf config.cluster.route53 {
      provider = "aws.us_east_2";
      name = "${config.cluster.domain}.";
    };

    resource.aws_route53_record = lib.mkIf config.cluster.route53 (let
      domains = lib.flatten
        (lib.flip lib.mapAttrsToList config.cluster.coreNodes
          (instanceName: instance:
            lib.forEach instance.route53.domains
            (domain: { ${domain} = instance.uid; })));
    in lib.flip lib.mapAttrs' (lib.zipAttrs domains) (domain: instanceUids:
      lib.nameValuePair "${config.cluster.name}-${
        lib.replaceStrings [ "." "*" ] [ "_" "_" ] domain
      }" {
        zone_id = id "data.aws_route53_zone.selected";
        name = domain;
        type = "A";
        ttl = "60";
        records =
          lib.forEach instanceUids (uid: var "aws_eip.${uid}.public_ip");
      }));

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

    data.aws_iam_policy_document = let
      # deploy for core role
      role = config.cluster.iam.roles.core;
      op = policyName: policy:
        lib.nameValuePair policy.uid {
          statement = {
            inherit (policy) effect actions resources;
          } // (lib.optionalAttrs (policy.condition != null) {
            inherit (policy) condition;
          });
        };
    in lib.listToAttrs (lib.mapAttrsToList op role.policies);

    resource.aws_iam_instance_profile =
      lib.flip lib.mapAttrs' config.cluster.coreNodes (name: coreNode:
        lib.nameValuePair coreNode.uid {
          name = coreNode.uid;
          inherit (coreNode.iam.instanceProfile) path;
          role = coreNode.iam.instanceProfile.role.tfName;
          lifecycle = [{ create_before_destroy = true; }];
        });

    resource.aws_iam_role = let
      # deploy for core role
      role = config.cluster.iam.roles.core;
    in {
      "${role.uid}" = {
        name = role.uid;
        assume_role_policy = role.assumePolicy.tfJson;
        lifecycle = [{ create_before_destroy = true; }];
      };
    };

    resource.aws_iam_role_policy = let
      # deploy for core role
      role = config.cluster.iam.roles.core;
      op = policyName: policy:
        lib.nameValuePair policy.uid {
          name = policy.uid;
          role = role.id;
          policy = var "data.aws_iam_policy_document.${policy.uid}.json";
        };
    in lib.listToAttrs (lib.mapAttrsToList op role.policies);

    resource.aws_security_group = {
      "${config.cluster.name}" = {
        provider = awsProviderFor config.cluster.region;
        name_prefix = "${config.cluster.name}-";
        description = "Security group for Core in ${config.cluster.name}";
        vpc_id = id "aws_vpc.core";
        lifecycle = [{ create_before_destroy = true; }];
      };
    };

    resource.aws_security_group_rule = let
      mapInstances = _: coreNode:
        merge (lib.flip lib.mapAttrsToList coreNode.securityGroupRules (_: rule:
          lib.listToAttrs (lib.flatten (lib.flip map rule.protocols (protocol:
            mkSecurityGroupRule {
              prefix = config.cluster.name;
              inherit (config.cluster) region;
              inherit rule protocol;
            })))));

      coreNodes' = lib.mapAttrsToList mapInstances config.cluster.coreNodes;
    in merge coreNodes';

    # ---------------------------------------------------------------
    # Core Instances
    # ---------------------------------------------------------------

    resource.aws_eip = lib.mapAttrs' (name: coreNode:
      lib.nameValuePair coreNode.uid {
        vpc = true;
        network_interface = id "aws_network_interface.${coreNode.uid}";
        tags = {
          Cluster = config.cluster.name;
          Name = coreNode.name;
        };
        lifecycle = [{ create_before_destroy = true; }];
      }) config.cluster.coreNodes;

    resource.aws_eip_association = lib.mapAttrs' (name: coreNode:
      lib.nameValuePair coreNode.uid {
        instance_id   = id "aws_instance.${name}";
        allocation_id = id "aws_eip.${coreNode.uid}";
      }) config.cluster.coreNodes;

    resource.aws_network_interface = lib.mapAttrs' (name: coreNode:
      lib.nameValuePair coreNode.uid {
        subnet_id = coreNode.subnet.id;
        security_groups = [ coreNode.securityGroupId ];
        private_ips = [ coreNode.privateIP ];
        tags = {
          Cluster = config.cluster.name;
          Name = coreNode.name;
        };
        lifecycle = [{ create_before_destroy = true; }];
      }) config.cluster.coreNodes;

    resource.aws_instance = lib.mapAttrs (name: coreNode:
      lib.mkMerge [
        (lib.mkIf coreNode.enable {
          depends_on = [ "aws_eip.${coreNode.uid}" ];
          inherit (coreNode) ami;
          instance_type = coreNode.instanceType;
          monitoring = true;

          tags = {
            Cluster = config.cluster.name;
            Name = name;
            UID = coreNode.uid;
            Consul = "server";
            Vault = "server";
            Nomad = "server";
            # Flake = coreNode.flake;
          } // coreNode.tags;

          root_block_device = {
            volume_type = "gp2";
            volume_size = coreNode.volumeSize;
            delete_on_termination = true;
          };

          iam_instance_profile = coreNode.iam.instanceProfile.tfName;

          network_interface = {
            network_interface_id = id "aws_network_interface.${coreNode.uid}";
            device_index = 0;
          };

          user_data = coreNode.userData;

          ebs_optimized =
            lib.mkIf (coreNode.ebsOptimized != null) coreNode.ebsOptimized;

          provisioner = let
            ssh = "${pkgs.openssh}/bin/ssh -C -oUserKnownHostsFile=/dev/null -oNumberOfPasswordPrompts=0 -oServerAliveInterval=60 -oControlPersist=600 -oStrictHostKeyChecking=no -i ./secrets/ssh-${config.cluster.name} ${target}";
            scp = "${pkgs.openssh}/bin/scp -C -oUserKnownHostsFile=/dev/null -oNumberOfPasswordPrompts=0 -oServerAliveInterval=60 -oControlPersist=600 -oStrictHostKeyChecking=no -i ./secrets/ssh-${config.cluster.name} ";
            target = "root@${var "aws_eip.${coreNode.uid}.public_ip"}";
          in (lib.optionals (name == "core-1") [{
              local-exec = {
                command = ''
                  echo
                  echo Waiting for ssh to come up on port 22 ...
                  while test -z "$(
                    ${pkgs.socat}/bin/socat \
                      -T2 stdout \
                      tcp:${var "aws_eip.${coreNode.uid}.public_ip"}:22,connect-timeout=2,readbytes=1 \
                      2>/dev/null
                  )"
                  do
                      printf " ."
                      sleep 5
                  done

                  sleep 1
                  if test -f ${relEncryptedFolder}/vault.enc.json; then
                    ${ssh} -- "mkdir -p /var/lib/private/vault"
                    ${scp} "${relEncryptedFolder}/vault.enc.json" "${target}:/var/lib/private/vault/vault.enc.json"
                    ${ssh} -- "touch /var/lib/private/vault/.bootstrap-done"
                  fi
                  if test -f ${relEncryptedFolder}/nomad.bootstrap.enc.json; then
                    tempfile=$(mktemp)
                    ${ssh} -- "mkdir -p /var/lib/nomad"
                    ${sopsDecrypt "${relEncryptedFolder}/nomad.bootstrap.enc.json"}|${pkgs.jq}/bin/jq -r '.token' > "$tempfile"
                    ${scp} "$tempfile" "${target}:/var/lib/nomad/bootstrap.token"
                    rm "$tempfile"
                    ${ssh} -- "touch /var/lib/nomad/.bootstrap-done"
                  fi
                '';
              };
            }]) ++ [
            {
              local-exec = {
                command = "${
                    self.nixosConfigurations."${config.cluster.name}-${name}".config.secrets.generateScript
                  }/bin/generate-secrets";
              };
            }
            {
              local-exec = let
                command =
                  coreNode.localProvisioner.protoCommand (var "aws_eip.${coreNode.uid}.public_ip");
              in {
                inherit command;
                inherit (coreNode.localProvisioner) interpreter environment;
                working_dir = coreNode.localProvisioner.workingDir;
              };
            }] ++
            (lib.optionals (name == "core-1") [{
              local-exec = {
                command = ''
                  echo
                  echo Waiting for ssh to come up on port 22 ...
                  while test -z "$(
                    ${pkgs.socat}/bin/socat \
                      -T2 stdout \
                      tcp:${var "aws_eip.${coreNode.uid}.public_ip"}:22,connect-timeout=2,readbytes=1 \
                      2>/dev/null
                  )"
                  do
                      printf " ."
                      sleep 5
                  done

                  sleep 1

                  if ! test -f ${relEncryptedFolder}/vault.enc.json; then
                    echo
                    echo Waiting for bootstrapping on core-1 to finish for vault /var/lib/vault/vault.enc.json ...
                    ${ssh} -- 'while ! test -f /var/lib/vault/vault.enc.json; do sleep 5; done'
                    echo ... found /var/lib/vault/vault.enc.json
                    secret="$(${ssh} cat /var/lib/vault/vault.enc.json)"
                    echo "$secret" > ${relEncryptedFolder}/vault.enc.json
                    ${pkgs.git}/bin/git add ${relEncryptedFolder}/vault.enc.json
                  fi
                  if ! test -f ${relEncryptedFolder}/nomad.bootstrap.enc.json; then
                    echo
                    echo Waiting for bootstrapping on core-1 to finish for nomad /var/lib/nomad/bootstrap.token ...
                    ${ssh} -- 'while ! test -f /var/lib/nomad/bootstrap.token; do sleep 5; done'
                    echo ... found /var/lib/nomad/bootstrap.token
                    secret="$(${ssh} -- cat /var/lib/nomad/bootstrap.token)"
                    echo "{}" | ${pkgs.jq}/bin/jq ".token = \"$secret\"" | ${sopsEncrypt} > ${relEncryptedFolder}/nomad.bootstrap.enc.json
                    ${pkgs.git}/bin/git add ${relEncryptedFolder}/nomad.bootstrap.enc.json
                  fi
                '';
              };
            }
          ]);
        })

        (lib.mkIf config.cluster.generateSSHKey {
          key_name = var "aws_key_pair.core.key_name";
        })
      ]) config.cluster.coreNodes;

    # ---------------------------------------------------------------
    # Extra Storage
    # ---------------------------------------------------------------
    resource.aws_volume_attachment = let
      storageNodes = lib.filterAttrs (_: v: v.ebsVolume != null) config.cluster.coreNodes;
    in lib.mkIf (storageNodes != {}) (lib.mapAttrs (
      # host name == volume name
      host: _: mkAttachment host host "/dev/sdh"
    ) storageNodes );

    # host name == volume name
    resource.aws_ebs_volume = let
      storageNodes = lib.filterAttrs (_: v: v.ebsVolume != null) config.cluster.coreNodes;
    in lib.mkIf (storageNodes != {}) (lib.mapAttrs (
      host: cfg: mkStorage host config.cluster.kms cfg.ebsVolume
    ) storageNodes );
  };
}
