{ self, lib, pkgs, config, terralib, ... }:
let
  inherit (terralib)
    var id pp regions awsProviderNameFor awsProviderFor mkSecurityGroupRule
    nullRoute;
  inherit (config.cluster) infraType vbkBackend vbkBackendSkipCertVerification;

  merge = lib.foldl' lib.recursiveUpdate { };
  tags = { Cluster = config.cluster.name; };

  infraTypeCheck = if builtins.elem infraType [ "aws" "premSim" ] then true else (throw ''
    To utilize the prem-sim TF attr, the cluster config parameter `infraType`
    must either "aws" or "premSim".
  '');
in {
  tf.prem-sim.configuration = lib.mkIf infraTypeCheck {
    terraform.backend.http = let
      vbk =
        "${vbkBackend}/state/${config.cluster.name}/prem-sim";
    in {
      address = vbk;
      lock_address = vbk;
      unlock_address = vbk;
      skip_cert_verification = vbkBackendSkipCertVerification;
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

    # ---------------------------------------------------------------
    # Networking
    # ---------------------------------------------------------------

    resource.aws_vpc.prem_sim = {
      provider = awsProviderFor config.cluster.region;
      lifecycle = [{ create_before_destroy = true; }];

      cidr_block = config.cluster.premSimVpc.cidr;
      enable_dns_hostnames = true;
      tags = {
        Cluster = config.cluster.name;
        Name = config.cluster.premSimVpc.name;
        Region = config.cluster.region;
      };
    };

    resource.aws_internet_gateway."${config.cluster.name}-premSim" = {
      lifecycle = [{ create_before_destroy = true; }];

      vpc_id = id "aws_vpc.prem_sim";
      tags = {
        Cluster = config.cluster.name;
        Name = "${config.cluster.name}-premSim";
      };
    };

    resource.aws_route_table."${config.cluster.name}-premSim" = {
      vpc_id = id "aws_vpc.prem_sim";
      lifecycle = [{ create_before_destroy = true; }];

      tags = {
        Cluster = config.cluster.name;
        Name = "${config.cluster.name}-premSim";
      };
    };

    resource.aws_route.prem_sim = nullRoute // {
      route_table_id = id "aws_route_table.${config.cluster.name}-premSim";
      destination_cidr_block = "0.0.0.0/0";
      gateway_id = id "aws_internet_gateway.${config.cluster.name}-premSim";
    };

    resource.aws_subnet = lib.flip lib.mapAttrs' config.cluster.premSimVpc.subnets
      (name: subnet:
        lib.nameValuePair subnet.name {
          provider = awsProviderFor config.cluster.vpc.region;
          vpc_id = id "aws_vpc.prem_sim";
          cidr_block = subnet.cidr;

          lifecycle = [{ create_before_destroy = true; }];

          tags = {
            Cluster = config.cluster.name;
            Name = subnet.name;
          };
        });

    resource.aws_route_table_association = lib.mapAttrs' (name: subnet:
      lib.nameValuePair "${config.cluster.name}-${name}-internet" {
        subnet_id = subnet.id;
        route_table_id = id "aws_route_table.${config.cluster.name}-premSim";
      }) config.cluster.premSimVpc.subnets;

    # ---------------------------------------------------------------
    # SSL/TLS - root ssh
    # ---------------------------------------------------------------

    # Prem simulated nodes share a keypair with aws cloud nodes
    resource.aws_key_pair.prem_sim = lib.mkIf (config.cluster.generateSSHKey) {
      provider = awsProviderFor config.cluster.region;
      key_name = "${config.cluster.name}-premSim";
      public_key = var ''file("secrets/ssh-${config.cluster.name}.pub")'';
    };

    # ---------------------------------------------------------------
    # Prem Simulation Instance IAM + Security Group
    # ---------------------------------------------------------------

    resource.aws_security_group = {
      "${config.cluster.name}-premSim" = {
        provider = awsProviderFor config.cluster.region;
        name_prefix = "${config.cluster.name}-premSim";
        description =
          "Security group for Simulated Premise Nodes in ${config.cluster.name}-premSim";
        vpc_id = id "aws_vpc.prem_sim";
        lifecycle = [{ create_before_destroy = true; }];
      };
    };

    resource.aws_security_group_rule = let
      mapPremInstances = _: premSimNode:
        merge (lib.flip lib.mapAttrsToList premSimNode.securityGroupRules
          (_: rule:
            lib.listToAttrs (lib.flatten (lib.flip map rule.protocols (protocol:
              mkSecurityGroupRule {
                prefix = "${config.cluster.name}-premSim";
                inherit (config.cluster) region;
                inherit rule protocol;
              })))));

      premSimNodes' =
        lib.mapAttrsToList mapPremInstances config.cluster.premSimNodes;
    in merge premSimNodes';

    # ---------------------------------------------------------------
    # Prem Sim Nodes
    # ---------------------------------------------------------------

    resource.aws_eip = lib.mapAttrs' (name: premSimNode:
      lib.nameValuePair premSimNode.uid {
        vpc = true;
        network_interface = id "aws_network_interface.${premSimNode.uid}";
        associate_with_private_ip = premSimNode.privateIP;
        tags = {
          Cluster = config.cluster.name;
          Name = premSimNode.name;
        };
        lifecycle = [{ create_before_destroy = true; }];
      }) config.cluster.premSimNodes;

    resource.aws_network_interface = lib.mapAttrs' (name: premSimNode:
      lib.nameValuePair premSimNode.uid {
        subnet_id = premSimNode.subnet.id;
        security_groups = [ premSimNode.securityGroupId ];
        private_ips = [ premSimNode.privateIP ];
        tags = {
          Cluster = config.cluster.name;
          Name = premSimNode.name;
        };
        lifecycle = [{ create_before_destroy = true; }];
      }) config.cluster.premSimNodes;

    resource.aws_instance = lib.mapAttrs (name: premSimNode:
      lib.mkMerge [
        (lib.mkIf premSimNode.enable {
          inherit (premSimNode) ami;
          instance_type = premSimNode.instanceType;
          monitoring = true;

          tags = {
            Cluster = config.cluster.name;
            Name = name;
            UID = premSimNode.uid;
            premSimulation = "true";
            # Flake = premSimNode.flake;
          } // premSimNode.tags;

          root_block_device = {
            volume_type = "gp2";
            volume_size = premSimNode.volumeSize;
            delete_on_termination = true;
          };

          # iam_instance_profile = premSimNode.iam.instanceProfile.tfName;

          network_interface = {
            network_interface_id = id "aws_network_interface.${premSimNode.uid}";
            device_index = 0;
          };

          user_data = premSimNode.userData;

          ebs_optimized =
            lib.mkIf (premSimNode.ebsOptimized != null) premSimNode.ebsOptimized;

          provisioner = [
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
                  premSimNode.localProvisioner.protoCommand (var "self.public_ip");
              in {
                inherit command;
                inherit (premSimNode.localProvisioner) interpreter environment;
                working_dir = premSimNode.localProvisioner.workingDir;
              };
            }
          ];
        })

        (lib.mkIf config.cluster.generateSSHKey {
          key_name = "${config.cluster.name}-premSim";
        })
      ]) config.cluster.premSimNodes;
  };
}
