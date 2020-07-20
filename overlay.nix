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

  vault-bin = prev.vault-bin.overrideAttrs (old: rec {
    version = "1.5.0-rc";
    src = prev.fetchurl {
      url =
        "https://releases.hashicorp.com/vault/${version}/vault_${version}_linux_amd64.zip";
      sha256 = "sha256-HAfRENfGbcrwrszmfCSCNlYVR6Ha5kM88k6efMnOCic=";
    };
  });

  consul = prev.callPackage ./pkgs/consul { };

  terraform-with-plugins = prev.terraform.withPlugins
    (plugins: lib.attrVals [ "null" "local" "aws" "tls" "sops" ] plugins);

  mkShellNoCC = prev.mkShell.override { stdenv = prev.stdenvNoCC; };

  mill = prev.callPackage ./pkgs/mill.nix { };

  recImport = prev.callPackage ./lib/rec-import.nix { };

  escapeUserData = prev.callPackage ./lib/escape-user-data.nix { };

  inherit (self.inputs.inclusive.lib) inclusive;

  inherit (self.inputs.nixpkgs-crystal.legacyPackages.${system}) crystal;

  pp = v: trace (toJSON v) v;

  inherit (self.inputs.bitte-cli.legacyPackages.${system}) bitte;

  devShell = final.callPackage ./pkgs/dev-shell.nix { };

  nixosModules = import ./pkgs/nixos-modules.nix { inherit nixpkgs lib; };

  sops-add = prev.callPackage ./pkgs/sops-add.nix { };

  envoy = prev.callPackage ./pkgs/envoy.nix { };

  nomad = prev.callPackage ./pkgs/nomad.nix { };

  haproxy = prev.callPackage ./pkgs/haproxy.nix { };

  consul-template = prev.callPackage ./pkgs/consul-template.nix { };

  toPrettyJSON = prev.callPackage ./lib/to-pretty-json.nix { };

  clusters = final.callPackage ./lib/clusters.nix { inherit self system; } {
    root = ./clusters;
  };

  nixosConfigurations = lib.pipe final.clusters [
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
