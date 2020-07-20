{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib) sops2kms sops2region cidrsOf;
  inherit (builtins) readFile replaceStrings;
  inherit (lib) mapAttrs' nameValuePair flip;
  inherit (config) cluster;
  inherit (cluster.vpc) subnets;
  inherit (import ./security-group-rules.nix { inherit config pkgs; })
    securityGroupRules;

  nixosAmis =
    import (self.inputs.nixpkgs + "/nixos/modules/virtualisation/ec2-amis.nix");

  amis = {
    nixos = mapAttrs' (name: value: nameValuePair name value.hvm-ebs)
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

in {

  imports = [ ./iam.nix ];

  cluster = {
    name = "atala-testnet";
    kms = availableKms.atala.eu-central-1;
    domain = "testnet.atalaprism.io";
    s3-bucket = "atala-cvp";
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

    autoscalingGroups = (flip mapAttrs' { "t3a.medium" = 3; }
      (instanceType: desiredCapacity:
        let saneName = "clients-${replaceStrings [ "." ] [ "-" ] instanceType}";
        in nameValuePair saneName {
          inherit desiredCapacity instanceType;
          associatePublicIP = true;
          maxInstanceLifetime = 604800;
          ami = amis.nixos.${cluster.region};
          iam.role = cluster.iam.roles.client;
          iam.instanceProfile.role = cluster.iam.roles.client;

          subnets = [ subnets.prv-1 subnets.prv-2 subnets.prv-3 ];

          modules = [ ../../../profiles/client.nix ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        }));

    instances = {
      core-1 = {
        instanceType = "t3a.medium";
        privateIP = "10.0.0.10";
        subnet = subnets.prv-1;
        iam.role = cluster.iam.roles.core;
        iam.instanceProfile.role = cluster.iam.roles.core;
        route53.domains =
          [ "consul" "vault" "nomad" "web" "landing" "connector" ];

        modules =
          [ ../../../profiles/core.nix ../../../profiles/bootstrapper.nix ];

        securityGroupRules = {
          inherit (securityGroupRules)
            internet internal ssh http https haproxyStats vault-http grpc;
        };
      };

      core-2 = {
        instanceType = "t3a.medium";
        privateIP = "10.0.32.10";
        subnet = subnets.prv-2;
        iam.role = cluster.iam.roles.core;
        iam.instanceProfile.role = cluster.iam.roles.core;

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "t3a.medium";
        privateIP = "10.0.64.10";
        subnet = subnets.prv-3;
        iam.role = cluster.iam.roles.core;
        iam.instanceProfile.role = cluster.iam.roles.core;

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };
    };
  };
}
