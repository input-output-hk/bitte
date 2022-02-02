{ self, lib, pkgs, config, terralib, ... }:

let
  inherit (builtins) replaceStrings;
  inherit (lib) nameValuePair listToAttrs forEach mkForce;
  inherit (config) cluster;
  inherit (import ./security-group-rules.nix { inherit config pkgs lib terralib; })
    securityGroupRules;

  # only true in bitte repo
  bitte = self;

in
{
  imports = [ ./iam.nix ];

  secrets.encryptedRoot = ../../encrypted;

  services.nomad.namespaces = {
    example-cluster.description = "Bitte nomad cluster!";
  };

  cluster = {
    name = "bitte-example";

    adminNames = [ ];
    developerGithubNames = [ ];
    developerGithubTeamNames = [ ];
    domain = "example.com";
    kms = "arn:aws:kms:eu-central-1:999999999999:key/doesnt-exist";
    s3Bucket = "fake-s3-bucket";
    terraformOrganization = "example-doesnt-exist";

    s3CachePubKey = "fake-key";
    flakePath = ../../..;

    autoscalingGroups = listToAttrs (forEach [
      {
        region = "eu-central-1";
      }
      {
        region = "us-east-2";
      }
      {
        region = "eu-west-1";
      }
    ]
      (args:
        let
          attrs = ({
            desiredCapacity = 1;
            maxSize = 2;
            instanceType = "c5.large";
            iam.role = cluster.iam.roles.client;
            iam.instanceProfile.role = cluster.iam.roles.client;
            node_class = "client";

            modules = [
              bitte.profiles.client
              "${self.inputs.nixpkgs}/nixos/modules/profiles/headless.nix"
              "${self.inputs.nixpkgs}/nixos/modules/virtualisation/ec2-data.nix"
            ];

            securityGroupRules = {
              inherit (securityGroupRules) internet internal ssh;
            };
          } // args);
          asgName = "client-${attrs.region}-${
            replaceStrings [ "." ] [ "-" ] attrs.instanceType
          }";
        in
        nameValuePair asgName attrs));

    instances = {
      core-1 = {
        instanceType = "t3a.large";
        privateIP = "172.16.0.10";
        subnet = cluster.vpc.subnets.core-1;
        volumeSize = 250;

        modules = [
          bitte.profiles.core
          bitte.profiles.bootstrapper
          ./nomad-autoscaler.nix
        ];

        securityGroupRules = {
          inherit (securityGroupRules)
            internet internal ssh http https haproxyStats vault-http grpc;
        };
      };

      core-2 = {
        instanceType = "t3a.large";
        privateIP = "172.16.1.10";
        subnet = cluster.vpc.subnets.core-2;
        volumeSize = 200;

        modules = [ bitte.profiles.core ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "t3a.large";
        privateIP = "172.16.2.10";
        subnet = cluster.vpc.subnets.core-3;
        volumeSize = 200;

        modules = [ bitte.profiles.core ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      nexus = {
        instanceType = "t3a.xlarge";
        privateIP = "172.16.0.30";
        subnet = cluster.vpc.subnets.core-1;
        volumeSize = 600;
        ami = "ami-0a1a94722dcbff94c";
        route53.domains = [ "nexus.${cluster.domain}" ];

        modules =
          [ bitte.profiles.monitoring ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh http https;
        };
      };

      #hydra = {
      #  instanceType = "m5.4xlarge";

      #  privateIP = "172.16.0.40";
      #  subnet = cluster.vpc.subnets.core-1;
      #  volumeSize = 600;
      #  ami = "ami-0a1a94722dcbff94c";

      #  route53.domains = [
      #    "hydra-wg.${cluster.domain}"
      #  ];

      #  modules =
      #    [ bitte.profiles.monitoring ./hydra.nix ];

      #  securityGroupRules = {
      #    inherit (securityGroupRules)
      #      # http https
      #      internet internal ssh wireguard;
      #  };
      #};

      monitoring = {
        instanceType = "t3a.xlarge";
        privateIP = "172.16.0.20";
        subnet = cluster.vpc.subnets.core-1;
        volumeSize = 600;
        ami = "ami-0a1a94722dcbff94c";

        route53.domains = [
          "consul.${cluster.domain}"
          "docker.${cluster.domain}"
          "monitoring.${cluster.domain}"
          "nomad.${cluster.domain}"
          "vault.${cluster.domain}"
        ];

        modules = [
          bitte.profiles.monitoring
          ./monitoring-server.nix
        ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh http;
        };
      };

      routing = {
        instanceType = "t3a.small";
        privateIP = "172.16.1.20";
        subnet = cluster.vpc.subnets.core-2;
        ami = "ami-0a1a94722dcbff94c";

        route53.domains = [ "*.${cluster.domain}" ];

        modules =
          [ bitte.profiles.routing ./traefik.nix ];

        securityGroupRules = {
          inherit (securityGroupRules)
            internet internal ssh http routing;
        };
      };
    };
  };
}
