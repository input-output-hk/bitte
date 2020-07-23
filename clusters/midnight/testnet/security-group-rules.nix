{ pkgs, config, ... }:
let
  inherit (pkgs.terralib) cidrsOf;
  inherit (config.cluster.vpc) subnets;
  global = "0.0.0.0/0";
in {
  # TODO: derive needed security groups from networking.firewall?
  securityGroupRules = {
    internet = {
      type = "egress";
      port = 0;
      protocols = [ "-1" ];
      cidrs = [ global ];
    };

    internal = {
      type = "ingress";
      port = 0;
      protocols = [ "-1" ];
      cidrs = cidrsOf subnets;
    };

    ssh = {
      port = 22;
      cidrs = [ global ];
    };

    http = {
      port = 80;
      cidrs = [ global ];
    };

    https = {
      port = 443;
      cidrs = [ global ];
    };

    grpc = {
      port = 4422;
      cidrs = [ global ];
    };

    promtail = {
      port = 3100;
      cidrs = cidrsOf subnets;
    };

    haproxyStats = {
      port = 1936;
      cidrs = [ global ];
    };

    vault-http = {
      port = 8200;
      cidrs = [ global ];
    };

    consul-serf-lan = {
      port = 8301;
      protocols = [ "tcp" "udp" ];
      self = true;
      cidrs = cidrsOf subnets;
    };

    consul-grpc = {
      port = 8502;
      protocols = [ "tcp" "udp" ];
      cidrs = cidrsOf subnets;
    };

    nomad-serf-lan = {
      port = 4648;
      protocols = [ "tcp" "udp" ];
      cidrs = cidrsOf subnets;
    };

    nomad-rpc = {
      port = 4647;
      cidrs = cidrsOf subnets;
    };

    nomad-http = {
      port = 4646;
      cidrs = cidrsOf subnets;
    };
  };
}
