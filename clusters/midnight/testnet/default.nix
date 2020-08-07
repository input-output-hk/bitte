{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib) sops2kms sops2region cidrsOf;
  inherit (builtins) readFile replaceStrings;
  inherit (lib) mapAttrs' nameValuePair flip attrValues listToAttrs forEach;
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
    midnight.eu-central-1 =
      "arn:aws:kms:eu-central-1:596662952274:key/44a983de-91d7-4748-9905-1062c3d94053";
  };

in {
  imports = [ ./iam.nix ];

  cluster = {
    name = "midnight-testnet";
    kms = availableKms.midnight.eu-central-1;
    domain = "bitte.project42.iohkdev.io";
    s3-bucket = "iohk-midnight-bitte";
    adminNames = [ "shay.bergmann" "manveru" ];

    autoscalingGroups = listToAttrs
      (forEach [ { region = "eu-central-1"; } { region = "us-east-2"; } ] (args:
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
        privateIP = "10.0.0.10";
        subnet = subnets.prv-1;
        route53.domains = [ "consul" "vault" "nomad" ];

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

        modules = [ ../../../profiles/core.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "t3a.medium";
        privateIP = "10.0.64.10";
        subnet = subnets.prv-3;

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
          inherit (securityGroupRules) internet internal ssh http promtail;
        };
      };
    };
  };
}
