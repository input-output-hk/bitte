{ self, lib, pkgs, config, ... }:
{
  cluster = {
    name = "testnet";
    domain = "bitte-tutorial.iohkdev.io";
    
    flakePath = ../..;
    
    instances = {
      core-1 = {
        instanceType = "t2.small";
        privateIP = "172.16.0.10";

        securityGroupRules = let
          vpcs = pkgs.terralib.vpcs config.cluster;
        
          global = [ "0.0.0.0/0" ];
          internal = [ config.cluster.vpc.cidr ]
            ++ (lib.flip lib.mapAttrsToList vpcs (region: vpc: vpc.cidr_block));
        in {
          internet = {
            type = "egress";
            port = 0;
            protocols = [ "-1" ];
            cidrs = global;
          };
    
          internal = {
            type = "ingress";
            port = 0;
            protocols = [ "-1" ];
            cidrs = internal;
          };
          
          ssh = {
            port = 22;
            cidrs = global;
          };
        };
      };

    };  
  };
}
