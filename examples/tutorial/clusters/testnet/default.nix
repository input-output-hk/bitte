{ self, lib, pkgs, config, ... }:
let
  inherit (import ./security-group-rules.nix { inherit config pkgs lib; })
    securityGroupRules;

  inherit (config) cluster;
  inherit (cluster.vpc) subnets;

  bitte = self.inputs.bitte;
in
{
  imports = [ ./iam.nix ];

  cluster = {
    name = "tutorial-testnet";
    domain = "bitte-tutorial.iohkdev.io";
    s3Bucket = "iohk-bitte-tutorial";
    kms = "arn:aws:kms:ap-southeast-2:596662952274:key/0984e3ae-62dd-42c1-a946-9ebff2373289";
    adminNames = [ "shay.bergmann" "manveru" "samuel.evans-powell" ];

    flakePath = ../..;
    
    instances = {
      core-1 = {
        instanceType = "t3a.medium";
        privateIP = "172.17.0.10";
        route53.domains = [ "consul" "vault" "nomad" ];
        subnet = subnets.prv-1;

        securityGroupRules = {
          inherit (securityGroupRules)
            internet internal ssh http https haproxyStats vault-http grpc;
        };

        modules = [
          (bitte + /profiles/core.nix)
          (bitte + /profiles/bootstrapper.nix)
          ./secrets.nix
        ];
      };

      core-2 = {
        instanceType = "t3a.medium";
        privateIP = "172.17.1.10";
        subnet = subnets.prv-2;

        modules = [ (bitte + /profiles/core.nix) ./secrets.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "t3a.medium";
        privateIP = "172.17.2.10";
        subnet = subnets.prv-3;

        modules = [ (bitte + /profiles/core.nix) ./secrets.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

    };  
  };
}
