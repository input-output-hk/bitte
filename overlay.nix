{ system, self }:
let
  inherit (self.inputs)
    nixpkgs nix ops-lib nixpkgs-terraform crystal bitte-cli inclusive;
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

  nixFlakes = prev.nixFlakes.overrideAttrs ({ patches ? [ ], ... }: {
    patches = [
      patches
      (prev.fetchpatch {
        url =
          "https://github.com/cleverca22/nix/commit/39c2f9fd1c2d2e25ed10b6c3919a01022297dc34.patch";
        sha256 = "sha256-6vwVTMC1eZnJqB6FGv3vsS2AZhz52j0exLeS2WsT6Y0=";
      })
    ];
  });

  # nix = prev.nixFlakes;

  vault-bin = prev.callPackage ./pkgs/vault-bin.nix { };

  ssm-agent = prev.callPackage ./pkgs/ssm-agent { };

  consul = prev.callPackage ./pkgs/consul { };

  terraform-with-plugins =
    nixpkgs-terraform.legacyPackages.${system}.terraform_0_12.withPlugins
    (plugins:
      lib.attrVals [
        "acme"
        "aws"
        "consul"
        "local"
        "nomad"
        "null"
        "sops"
        "tls"
        "vault"
      ] plugins);

  mkShellNoCC = prev.mkShell.override { stdenv = prev.stdenvNoCC; };

  mill = prev.callPackage ./pkgs/mill.nix { };

  recImport = prev.callPackage ./lib/rec-import.nix { };

  escapeUserData = prev.callPackage ./lib/escape-user-data.nix { };

  snakeCase = prev.callPackage ./lib/snake-case.nix { };

  inherit (inclusive.lib) inclusive;
  inherit (crystal.packages.${system}) crystal;
  inherit (bitte-cli.packages.${system}) bitte;

  pp = v: trace (toJSON v) v;

  haproxy-auth-request = prev.callPackage ./pkgs/haproxy-auth-request.nix { };

  haproxy-cors = prev.callPackage ./pkgs/haproxy-cors.nix { };

  devShell = final.callPackage ./pkgs/dev-shell.nix { };

  nixosModules = import ./pkgs/nixos-modules.nix { inherit nixpkgs lib; };

  consulRegister = prev.callPackage ./pkgs/consul-register.nix { };

  systemd-runner = final.callPackage ./pkgs/systemd_runner { };

  envoy = prev.callPackage ./pkgs/envoy.nix { };

  nomad = prev.callPackage ./pkgs/nomad.nix { };

  seaweedfs = prev.callPackage ./pkgs/seaweedfs.nix { };

  boundary = prev.callPackage ./pkgs/boundary.nix { };

  grpcdump = prev.callPackage ./pkgs/grpcdump.nix { };

  haproxy = prev.callPackage ./pkgs/haproxy.nix { };

  grafana-loki = prev.callPackage ./pkgs/loki.nix { };

  grafana = prev.callPackage ./pkgs/grafana.nix { };

  victoriametrics = prev.callPackage ./pkgs/victoriametrics.nix { };

  consul-template = prev.callPackage ./pkgs/consul-template.nix { };

  nomad-autoscaler = prev.callPackage ./pkgs/nomad-autoscaler.nix { };

  toPrettyJSON = prev.callPackage ./lib/to-pretty-json.nix { };

  mkNomadJob = final.callPackage ./lib/mk-nomad-job.nix { };

  systemdSandbox = final.callPackage ./lib/systemd-sandbox.nix { };

  scaler-guard = let deps = with final; [ awscli bash curl jq nomad ];
  in prev.runCommandLocal "scaler-guard" {
    script = ./scripts/scaler-guard.sh;
    nativeBuildInputs = [ prev.makeWrapper ];
  } ''
    makeWrapper $script $out/bin/scaler-guard \
      --prefix PATH : ${prev.lib.makeBinPath deps}
  '';

  mkClusters = args:
    import ./lib/clusters.nix ({
      pkgs = final;
      lib = final.lib;
    } // args);

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
      egress_only_gateway_id = null;
      instance_id = null;
      ipv6_cidr_block = null;
      local_gateway_id = null;
      nat_gateway_id = null;
      network_interface_id = null;
      transit_gateway_id = null;
      vpc_peering_connection_id = null;
      gateway_id = null;
    };

    vpcs = cluster:
      lib.forEach (builtins.attrValues cluster.autoscalingGroups)
      (asg: asg.vpc);

    mapVpcs = cluster: f:
      lib.listToAttrs (lib.flatten (lib.forEach (vpcs cluster) f));

    mapVpcsToList = cluster: lib.forEach (vpcs cluster);

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
      checks = lib.concatStringsSep "\n" (lib.forEach services (service:
        "${prev.systemd}/bin/systemctl is-active '${service}.service'"));
    in prev.writeShellScript "check" ''
      set -exuo pipefail
      ${checks}
    '';

  ssh-keys = let
    authorized_keys = lib.fileContents ../modules/ssh_keys/authorized_keys;
    keys = import (ops-lib + "/overlays/ssh-keys.nix") lib;
    inherit (keys) allKeysFrom devOps;
  in { devOps = allKeysFrom devOps; };
}
