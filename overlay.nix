inputs:
let
  inherit (inputs) nixpkgs nixpkgs-2105 nix ops-lib nixpkgs-terraform bitte-cli;
  inherit (builtins) fromJSON toJSON trace mapAttrs genList foldl';
  inherit (nixpkgs) lib;
in final: prev: {
  nixos-rebuild = bitte-cli.packages.${final.system}.nixos-rebuild;
  bitte = bitte-cli.defaultPackage.${final.system};

  # this is temporary until we switch over
  inherit (nixpkgs-2105.legacyPackages.${final.system}) consul-template cue vault-bin haproxy;

  # nix = prev.nixFlakes;
  nixFlakes = inputs.nix.packages.${final.system}.nix;

  ssm-agent = prev.callPackage ./pkgs/ssm-agent { };

  consul = prev.callPackage ./pkgs/consul { };

  terraform-provider-names =
    [ "acme" "aws" "consul" "local" "nomad" "null" "sops" "tls" "vault" ];

  terraform-provider-versions = lib.listToAttrs (map (name:
    let
      provider = final.terraform-providers.${name};
      provider-source-address =
        provider.provider-source-address or "registry.terraform.io/nixpkgs/${name}";
      parts = lib.splitString "/" provider-source-address;
      source = lib.concatStringsSep "/" (lib.tail parts);
    in lib.nameValuePair name {
      inherit source;
      version = "= ${provider.version}";
    }) final.terraform-provider-names);

  nixpkgs-terraform-pkgs = nixpkgs-terraform.legacyPackages.${final.system};

  inherit (inputs.hydra-provisioner.packages.${final.system}) hydra-provisioner;
  inherit (final.nixpkgs-terraform-pkgs)
    terraform_0_13 terraform_0_14 terraform-providers;

  # terraform-with-plugins = final.terraform_0_14.withPlugins
  #   (plugins: lib.attrVals final.terraform-provider-names plugins);

  terraform-with-plugins = final.terraform_0_13.withPlugins
    (plugins: lib.attrVals final.terraform-provider-names plugins);

  mkShellNoCC = prev.mkShell.override { stdenv = prev.stdenvNoCC; };

  mill = prev.callPackage ./pkgs/mill.nix { };

  recImport = prev.callPackage ./lib/rec-import.nix { };

  sanitize = prev.callPackage ./lib/sanitize.nix { };

  snakeCase = prev.callPackage ./lib/snake-case.nix { };

  pp = v: trace (toJSON v) v;

  haproxy-auth-request = prev.callPackage ./pkgs/haproxy-auth-request.nix { };

  haproxy-cors = prev.callPackage ./pkgs/haproxy-cors.nix { };

  devShell = final.callPackage ./pkgs/dev-shell.nix { };
  genericShell = final.callPackage ./pkgs/generic-shell.nix { };

  consulRegister = prev.callPackage ./pkgs/consul-register.nix { };

  envoy = prev.callPackage ./pkgs/envoy.nix { };

  nomad = prev.callPackage ./pkgs/nomad.nix { inherit (inputs) nomad-source; };

  boundary = prev.callPackage ./pkgs/boundary.nix { };

  grpcdump = prev.callPackage ./pkgs/grpcdump.nix { };

  inherit (inputs.nixpkgs-unstable.legacyPackages.${final.system})
    grafana-loki grafana traefik;

  glusterfs =
    (inputs.nixpkgs-unstable.legacyPackages.${final.system}).callPackage
    ./pkgs/glusterfs.nix { };

  victoriametrics = prev.callPackage ./pkgs/victoriametrics.nix { };

  nomad-autoscaler = prev.callPackage ./pkgs/nomad-autoscaler.nix { };

  toPrettyJSON = prev.callPackage ./lib/to-pretty-json.nix { };

  mkNomadJob = final.callPackage ./lib/mk-nomad-job.nix { };

  vault-backend = final.callPackage ./pkgs/vault-backend.nix { };

  oauth2_proxy = final.callPackage ./pkgs/oauth2_proxy.nix { };

  filebeat = final.callPackage ./pkgs/filebeat.nix {
    inherit (inputs.nixpkgs-unstable.legacyPackages.${final.system})
      buildGoModule;
  };

  # Little convenience function helping us to containing the bash
  # madness: forcing our bash scripts to be shellChecked.
  writeBashChecked = final.writers.makeScriptWriter {
    interpreter = "${final.bash}/bin/bash";
    check = final.writers.writeBash "shellcheck-check" ''
      ${final.shellcheck}/bin/shellcheck "$1"
    '';
  };
  writeBashBinChecked = name: final.writeBashChecked "/bin/${name}";

  zfsAmi = {
    # attrs of interest:
    # * config.system.build.zfsImage
    # * config.system.build.uploadAmi
    zfs-ami = import "${nixpkgs}/nixos" {
      system = "x86_64-linux";
      configuration = { pkgs, lib, ... }: {
        imports = [
          ops-lib.nixosModules.make-zfs-image
          ops-lib.nixosModules.zfs-runtime
          "${nixpkgs}/nixos/modules/profiles/headless.nix"
          "${nixpkgs}/nixos/modules/virtualisation/ec2-data.nix"
        ];
        nix.package = final.nixFlakes;
        nix.extraOptions = ''
          experimental-features = nix-command flakes
        '';
        systemd.services.amazon-shell-init.path = [ final.sops ];
        nixpkgs.config.allowUnfreePredicate = x:
          builtins.elem (lib.getName x) [ "ec2-ami-tools" "ec2-api-tools" ];
        zfs.regions = [
          "eu-west-1"
          "ap-northeast-1"
          "ap-northeast-2"
          "eu-central-1"
          "us-east-2"
        ];
      };
    };
  };

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
      vpc_endpoint_id = null;
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
          (common // { cidr_blocks = lib.unique rule.cidrs; }));

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
    keys = import (ops-lib + "/overlays/ssh-keys.nix") lib;
    inherit (keys) allKeysFrom devOps;
  in { devOps = allKeysFrom devOps; };
}
