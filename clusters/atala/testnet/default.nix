{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib) sops2kms sops2region cidrsOf;
  inherit (builtins) readFile replaceStrings;
  inherit (lib) mapAttrs' nameValuePair flip attrValues;
  inherit (config) cluster;
  inherit (cluster.vpc) subnets;
  inherit (import ./security-group-rules.nix { inherit config pkgs; })
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
    s3-bucket = "atala-cvp";

    autoscalingGroups = (flip mapAttrs' { "t3a.medium" = 3; }
      (instanceType: desiredCapacity:
        let saneName = "client-${replaceStrings [ "." ] [ "-" ] instanceType}";
        in nameValuePair saneName {
          inherit desiredCapacity instanceType;
          associatePublicIP = true;
          maxInstanceLifetime = 604800;
          iam.role = cluster.iam.roles.client;
          iam.instanceProfile.role = cluster.iam.roles.client;

          subnets = attrValues subnets;

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
        route53.domains = [ "landing" ];

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "t3a.medium";
        privateIP = "10.0.64.10";
        subnet = subnets.prv-3;
        route53.domains = [ "landing" ];

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      monitoring = {
        instanceType = "t3a.large";
        privateIP = "10.0.0.20";
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
