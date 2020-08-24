{ system, self }:
let
  inherit (self.inputs) nixpkgs nix ops-lib;
  inherit (builtins) fromJSON toJSON trace mapAttrs genList foldl';
  inherit (nixpkgs) lib;
in final: prev: {
  inherit self;

  nixos-rebuild = let
    nixos = lib.nixosSystem {
      inherit system;
      modules = [{ nix.package = prev.nixFlakes; }];
    };
  in nixos.config.system.build.nixos-rebuild;

  # nix = prev.nixFlakes;

  ssm-agent = prev.callPackage ./pkgs/ssm-agent { };

  vault-bin = prev.callPackage ./pkgs/vault-bin.nix { };

  consul = prev.callPackage ./pkgs/consul { };

  terraform-with-plugins = prev.terraform.withPlugins (plugins:
    lib.attrVals [ "null" "local" "aws" "tls" "sops" "consul" "acme" "null" ]
    plugins);

  mkShellNoCC = prev.mkShell.override { stdenv = prev.stdenvNoCC; };

  mill = prev.callPackage ./pkgs/mill.nix { };

  recImport = prev.callPackage ./lib/rec-import.nix { };

  escapeUserData = prev.callPackage ./lib/escape-user-data.nix { };

  snakeCase = prev.callPackage ./lib/snake-case.nix { };

  inherit (self.inputs.inclusive.lib) inclusive;

  inherit (self.inputs.nixpkgs-crystal.legacyPackages.${system}) crystal;

  pp = v: trace (toJSON v) v;

  inherit (self.inputs.bitte-cli.legacyPackages.${system}) bitte;

  devShell = final.callPackage ./pkgs/dev-shell.nix { };

  nixosModules = import ./pkgs/nixos-modules.nix { inherit nixpkgs lib; };

  consulRegister = prev.callPackage ./pkgs/consul-register.nix { };

  envoy = prev.callPackage ./pkgs/envoy.nix { };

  nomad = prev.callPackage ./pkgs/nomad.nix { };

  haproxy = prev.callPackage ./pkgs/haproxy.nix { };

  consul-template = prev.callPackage ./pkgs/consul-template.nix { };

  nomad-autoscaler = prev.callPackage ./pkgs/nomad-autoscaler.nix { };

  toPrettyJSON = prev.callPackage ./lib/to-pretty-json.nix { };

  mkNomadJob = final.callPackage ./lib/mk-nomad-job.nix { };

  mkNomadTaskSandbox = final.callPackage ./lib/mk-nomad-task-sandbox.nix { };

  clusters = final.mkClusters {
    root = ./clusters;
    inherit self system;
  };

  mkClusters = args:
    import ./lib/clusters.nix ({
      pkgs = final;
      lib = final.lib;
    } // args);

  nixosConfigurations = final.mkNixosConfigurations final.clusters;

  mkNixosConfigurations = clusters:
    lib.pipe clusters [
      (lib.mapAttrsToList (clusterName: cluster:
        lib.mapAttrsToList
        (name: value: lib.nameValuePair "${clusterName}-${name}" value)
        (cluster.nodes // cluster.groups)))
      lib.flatten
      lib.listToAttrs
    ];

  terralib = rec {
    amis = import (nixpkgs + "/nixos/modules/virtualisation/ec2-amis.nix");

    var = v: "\${${v}}";
    id = v: var "${v}.id";
    pp = v: trace (toJSON v) v;

    readJSON = file: fromJSON (lib.fileContents file);
    sops2kms = file: (lib.elemAt (readJSON file).sops.kms 0).arn;
    sops2region = file: lib.elemAt (lib.splitString ":" (sops2kms file)) 3;

    cidrsOf = lib.mapAttrsToList (_: subnet: subnet.cidr);

    awsProviderNameFor = region: lib.replaceStrings [ "-" ] [ "_" ] region;
    awsProviderFor = region: "aws.${awsProviderNameFor region}";

    merge = lib.foldl' lib.recursiveUpdate { };

    nullRoute = {
      gateway_id = null;
      egress_only_gateway_id = null;
      instance_id = null;
      ipv6_cidr_block = null;
      nat_gateway_id = null;
      network_interface_id = null;
      transit_gateway_id = null;
      vpc_peering_connection_id = null;
    };

    # We technically only need three subnets, but dividing my 3 is pretty hard with CIDRs.
    # This still gives us 16382 addresses per subnet, which should be enough for a while.
    vpcs = cluster:
      lib.listToAttrs (lib.flip lib.imap0 [
        # "ap-east-1"
        "ap-northeast-1"
        "ap-northeast-2"
        # "ap-south-1"
        # "ap-southeast-1"
        # "ap-southeast-2"
        # "ca-central-1"
        "eu-central-1"
        # "eu-north-1"
        # "eu-west-1"
        # "eu-west-2"
        # "eu-west-3"
        # # "me-south-1"
        # "sa-east-1"
        # "us-east-1"
        "us-east-2"
        # "us-west-1"
        # "us-west-2"
      ] (index: region:
        lib.nameValuePair region {
          name = "${cluster.name}-${region}-asgs";
          vpc_id = id "aws_vpc.${region}";
          cidr_block = "10.${toString index}.0.0/16";
          provider = awsProviderFor region;
          subnets = {
            a = "10.${toString index}.0.0/18";
            b = "10.${toString index}.64.0/18";
            c = "10.${toString index}.128.0/18";
            d = "10.${toString index}.192.0/18";
          };
        }));

    regions = [
      # "ap-east-1"
      "ap-northeast-1"
      "ap-northeast-2"
      "ap-south-1"
      "ap-southeast-1"
      "ap-southeast-2"
      "ca-central-1"
      "eu-central-1"
      "eu-north-1"
      "eu-west-1"
      "eu-west-2"
      "eu-west-3"
      # "me-south-1"
      "sa-east-1"
      "us-east-1"
      "us-east-2"
      "us-west-1"
      "us-west-2"
    ];

    mkSecurityGroupRule = ({ region, prefix, rule, protocol }:
      let
        common = {
          provider = awsProviderFor region;
          type = rule.type;
          from_port = rule.from;
          to_port = rule.to;
          protocol = protocol;
          security_group_id = rule.securityGroupId;
        };

        from-self = (lib.nameValuePair
          "${prefix}-${rule.type}-${protocol}-${rule.name}-self"
          (common // { self = true; }));

        from-cidr = (lib.nameValuePair
          "${prefix}-${rule.type}-${protocol}-${rule.name}-cidr"
          (common // { cidr_blocks = rule.cidrs; }));

        from-ssgi = (lib.nameValuePair
          "${prefix}-${rule.type}-${protocol}-${rule.name}-ssgi" (common // {
            source_security_group_id = rule.sourceSecurityGroupId;
          }));

      in (lib.optional (rule.self != false) from-self)
      ++ (lib.optional (rule.cidrs != [ ]) from-cidr)
      ++ (lib.optional (rule.sourceSecurityGroupId != null) from-ssgi));
  };

  # systemd will not try to restart services whose dependencies have failed.
  # so we turn that into actual unit failures instead.
  ensureDependencies = services:
    let
      script = prev.writeShellScriptBin "check" ''
        set -exuo pipefail
        for service in ${toString services}; do
          ${prev.systemd}/bin/systemctl is-active "$service.service"
        done
      '';
    in "${script}/bin/check";

  ssh-keys = let
    authorized_keys = lib.fileContents ../modules/ssh_keys/authorized_keys;
    keys = import (ops-lib + "/overlays/ssh-keys.nix") lib;
    inherit (keys) allKeysFrom devOps;
  in { devOps = allKeysFrom devOps; };
}
