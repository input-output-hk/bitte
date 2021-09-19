{ self, lib, pkgs, config, ... }:
let
  inherit (pkgs.terralib) sops2kms sops2region cidrsOf;
  inherit (builtins) readFile replaceStrings;
  inherit (lib) mapAttrs' nameValuePair flip attrValues listToAttrs forEach;
  inherit (config) cluster;
  inherit (import ./security-group-rules.nix { inherit config pkgs lib; })
    securityGroupRules;

  bitte = self.inputs.bitte;

in {
  imports = [ ./iam.nix ./nix.nix ];

  services.nomad.namespaces = {
    example-cluster.description = "Example Cluster";
  };

  services.consul.policies.developer.servicePrefix."example-" = {
    policy = "write";
    intentions = "write";
  };

  services.nomad.policies = {
    admin.namespace."example-*".policy = "write";
    developer = {
      namespace."example-*".policy = "write";
      agent.policy = "read";
      quota.policy = "read";
      node.policy = "read";
      hostVolume."*".policy = "read";
    };
  };

  cluster = {
    name = "example-cluster";

    adminNames = [ ];
    developerGithubNames = [ ];
    developerGithubTeamNames = [ ];
    domain = "changeme.example.com";
    kms =
      "arn:aws:kms:eu-central-1:000000000000:key/00000000-0000-0000-0000-000000000000";
    s3Bucket = "org-example-bitte";
    terraformOrganization = "changeme";

    s3CachePubKey = lib.fileContents "${config.secrets.encryptedRoot}/nix-public-key-file";
    flakePath = ../../..;

    autoscalingGroups = listToAttrs (forEach [{
      region = "eu-central-1";
      desiredCapacity = 1;
    }] (args:
      let
        attrs = ({
          desiredCapacity = 1;
          maxSize = 40;
          instanceType = "c5.2xlarge";
          associatePublicIP = true;
          maxInstanceLifetime = 0;
          iam.role = cluster.iam.roles.client;
          iam.instanceProfile.role = cluster.iam.roles.client;

          modules = [
            (bitte + /profiles/client.nix)
            (bitte + /profiles/zfs-runtime.nix)
            "${self.inputs.nixpkgs}/nixos/modules/profiles/headless.nix"
            "${self.inputs.nixpkgs}/nixos/modules/virtualisation/ec2-data.nix"
            ./secrets.nix
            ./nix.nix
            ./reserve.nix
          ];

          securityGroupRules = {
            inherit (securityGroupRules)
              internet internal ssh example-rpc example-server;
          };
        } // args);
        asgName = "client-${attrs.region}-${
            replaceStrings [ "." ] [ "-" ] attrs.instanceType
          }";
      in nameValuePair asgName attrs));

    instances = {
      core-1 = {
        instanceType = "r5a.xlarge";
        privateIP = "172.16.0.10";
        subnet = cluster.vpc.subnets.core-1;
        volumeSize = 100;

        modules = [
          (bitte + /profiles/core.nix)
          (bitte + /profiles/bootstrapper.nix)
          ./secrets.nix
        ];

        securityGroupRules = {
          inherit (securityGroupRules)
            internet internal ssh http https haproxyStats vault-http grpc;
        };
      };

      core-2 = {
        instanceType = "r5a.xlarge";
        privateIP = "172.16.1.10";
        subnet = cluster.vpc.subnets.core-2;
        volumeSize = 100;

        modules = [ (bitte + /profiles/core.nix) ./secrets.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "r5a.xlarge";
        privateIP = "172.16.2.10";
        subnet = cluster.vpc.subnets.core-3;
        volumeSize = 100;

        modules = [ (bitte + /profiles/core.nix) ./secrets.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      monitoring = {
        instanceType = "t3a.large";
        privateIP = "172.16.0.20";
        subnet = cluster.vpc.subnets.core-1;
        volumeSize = 1000;
        route53.domains = [
          "consul.${cluster.domain}"
          "docker.${cluster.domain}"
          "monitoring.${cluster.domain}"
          "nomad.${cluster.domain}"
          "vault.${cluster.domain}"
        ];

        modules = [
          (bitte + /profiles/monitoring.nix)
          ./monitoring-server.nix
          ./secrets.nix
        ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh http;
        };
      };

      routing = {
        instanceType = "t3a.small";
        privateIP = "172.16.1.20";
        subnet = cluster.vpc.subnets.core-2;
        volumeSize = 100;
        route53.domains = [ "*.${cluster.domain}" ];

        modules =
          [ (bitte + /profiles/routing.nix) ./secrets.nix ./traefik.nix ];

        securityGroupRules = {
          inherit (securityGroupRules)
            internet internal ssh http routing example-server-public
            example-discovery-public;
        };
      };
    };
  };
}
