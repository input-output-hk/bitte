final: prev:
let
  inherit (builtins) fromJSON toJSON trace mapAttrs genList foldl';
  inherit (final) lib;
in
{
  vault-bin = final.vault;
  ssm-agent = prev.callPackage ./pkgs/ssm-agent { };

  consul = prev.callPackage ./pkgs/consul { };

  terraform-with-plugins = prev.terraform_0_12.withPlugins
  (plugins: let
    vault = plugins.vault.overrideAttrs (o: let
      version = "2.14.0";
      rev = "v${version}";
      sha256 = "sha256-CeZIBuy00HGXAFDuiYEKm11o0ylkMAl07wa+zL9EW3E=";
      passthru = o.passthru // { inherit version rev sha256; };

    in {
      inherit version passthru;
      src = final.fetchFromGitHub {
        inherit (passthru) owner repo rev sha256;
      };
      postBuild = "mv $NIX_BUILD_TOP/go/bin/${passthru.repo}{,_v${passthru.version}}";
    });

    aws = plugins.aws.overrideAttrs (o: let
      version = "3.21.0";
      rev = "v${version}";
      sha256 = "sha256:0nb03xykjj4a3lvfbbz1l31j6czii5xgslznq8vw0x9v9birjj1v";
      passthru = o.passthru // { inherit version rev sha256; };
    in {
      inherit version passthru;
      src = final.fetchFromGitHub {
        inherit (passthru) owner repo rev sha256;
      };
      postBuild = "mv $NIX_BUILD_TOP/go/bin/${passthru.repo}{,_v${passthru.version}}";
    });
  in [ vault aws plugins.null ]
  ++ (with plugins; [ acme consul local nomad sops tls ]));

  mkShellNoCC = prev.mkShell.override { stdenv = prev.stdenvNoCC; };

  mill = prev.callPackage ./pkgs/mill.nix { };

  recImport = prev.callPackage ./lib/rec-import.nix { };

  escapeUserData = prev.callPackage ./lib/escape-user-data.nix { };

  snakeCase = prev.callPackage ./lib/snake-case.nix { };

  pp = v: trace (toJSON v) v;

  haproxy-auth-request = prev.callPackage ./pkgs/haproxy-auth-request.nix { };

  haproxy-cors = prev.callPackage ./pkgs/haproxy-cors.nix { };

  devShell = prev.callPackage ./pkgs/dev-shell.nix { };

  genericShell = final.callPackage ./pkgs/generic-shell.nix { };

  mkBitteShell = {
    cluster
  , self
  , profile
  , nixConf ? null
  }: let
    cfg = self.clusters.${final.system}.${cluster}.proto.config.cluster;
    inherit (cfg) domain region;
  in final.genericShell.overrideAttrs (o: {
    BITTE_CLUSTER = cluster;
    AWS_PROFILE = profile;
    AWS_DEFAULT_REGION = region;
    VAULT_ADDR = "https://vault.${domain}";
    NOMAD_ADDR = "https://nomad.${domain}";
    CONSUL_HTTP_ADDR = "https://consul.${domain}";
    NIX_USER_CONF_FILES = with lib; concatStringsSep ":"
    ((toList o.NIX_USER_CONF_FILES) ++ (optional (nixConf != null) nixConf));
  });

  consulRegister = prev.callPackage ./pkgs/consul-register.nix { };

  # systemd-runner = final.callPackage ./pkgs/systemd_runner { };

  envoy = prev.callPackage ./pkgs/envoy.nix { };

  nomad =
    prev.callPackage ./pkgs/nomad.nix {};

  levant =
    prev.callPackage ./pkgs/levant.nix {};

  seaweedfs = prev.callPackage ./pkgs/seaweedfs.nix { };

  boundary = prev.callPackage ./pkgs/boundary.nix { };

  grpcdump = prev.callPackage ./pkgs/grpcdump.nix { };

  # haproxy = prev.callPackage ./pkgs/haproxy.nix { };

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

  terralib = rec {
    amis = import (final.path + "/nixos/modules/virtualisation/ec2-amis.nix");

    earlyVar = v:
    lib.fileContents (
      final.runCommand "terraform-early-var" {
        buildInputs = [ final.terraform ];
      } ''
        cat <<'EOF' | terraform console > $out
        "${v}"
        EOF
      '');

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
      vpc_endpoint_id = null;
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
}
