{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib) sops2kms sops2region cidrsOf;
  inherit (builtins) readFile replaceStrings;
  inherit (lib) mapAttrs' nameValuePair flip attrValues listToAttrs forEach;
  inherit (config) cluster;
  inherit (cluster.vpc) subnets;
  inherit (import ./security-group-rules.nix { inherit config lib pkgs; })
    securityGroupRules;

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
    s3Bucket = "atala-cvp";

    autoscalingGroups = listToAttrs (forEach [
      {
        region = "eu-central-1";
        desiredCapacity = 1;
        vpc = {
          region = "eu-central-1";
          cidr = "10.0.0.0/22";
          subnets = {
            "eu-central-1-clients-1".cidr = "10.0.0.0/24";
            "eu-central-1-clients-2".cidr = "10.0.1.0/24";
            "eu-central-1-clients-3".cidr = "10.0.2.0/24";
          };
        };
      }
      {
        region = "us-east-2";
        desiredCapacity = 1;
        vpc = {
          region = "us-east-2";
          cidr = "10.0.4.0/22";
          subnets = {
            "us-east-2-clients-1".cidr = "10.0.4.0/24";
            "us-east-2-clients-2".cidr = "10.0.5.0/24";
            "us-east-2-clients-3".cidr = "10.0.6.0/24";
          };
        };
      }
    ] (args:
      let
        attrs = ({
          desiredCapacity = 1;
          instanceType = "t3a.medium";
          associatePublicIP = true;
          maxInstanceLifetime = 604800;
          iam.role = cluster.iam.roles.client;
          iam.instanceProfile.role = cluster.iam.roles.client;

          modules = [ ../../../profiles/client.nix ];

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        } // args);
        asgName = "client-${attrs.region}-${
            replaceStrings [ "." ] [ "-" ] attrs.instanceType
          }";
      in nameValuePair asgName attrs));

    instances = {
      core-1 = {
        instanceType = "t3a.medium";
        privateIP = "172.16.0.10";
        subnet = subnets.prv-1;
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
        privateIP = "172.16.1.10";
        subnet = subnets.prv-2;
        route53.domains = [ "landing" ];

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "t3a.medium";
        privateIP = "172.16.2.10";
        subnet = subnets.prv-3;
        route53.domains = [ "landing" ];

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      monitoring = {
        instanceType = "t3a.large";
        privateIP = "172.16.0.20";
        subnet = subnets.prv-1;
        route53.domains = [ "monitoring" ];

        modules = [ ../../../profiles/monitoring.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh http;
        };
      };
    };
  };
}
