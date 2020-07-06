{ system, self }:
let
  inherit (self.inputs) nixpkgs nix nomadix terranix ops-lib;
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
    version = "1.4.2";
    src = prev.fetchurl {
      url =
        "https://releases.hashicorp.com/vault/${version}/vault_${version}_linux_amd64.zip";
      sha256 = "sha256-8ryonL/7hxAmXrA7yUUswxawMzjEEbqEU//nQZOQuPE=";
    };
  });

  ipxe = prev.callPackage ./pkgs/ipxe.nix {
    inherit self;
    embedScript = prev.writeText "ipxe" ''
      #!ipxe

      echo Amazon EC2 - iPXE boot via user-data
      echo CPU: ''${cpuvendor} ''${cpumodel}
      ifstat ||
      dhcp ||
      route ||
      chain -ar http://169.254.169.254/latest/user-data
    '';
  };

  inherit (self.inputs.nixpkgs-master.legacyPackages.${system}) consul;

  terraform-with-plugins = prev.terraform.withPlugins
    (plugins: lib.attrVals [ "null" "local" "aws" "tls" "sops" ] plugins);

  mkShellNoCC = prev.mkShell.override { stdenv = prev.stdenvNoCC; };

  ec2-ipxe = prev.callPackage ./pkgs/ec2-ipxe.nix { };

  mill = prev.callPackage ./pkgs/mill.nix { };

  recImport = prev.callPackage ./lib/rec-import.nix { };

  escapeUserData = prev.callPackage ./lib/escape-user-data.nix { };

  writeRubyBin = prev.callPackage ./lib/write-ruby-bin.nix { };

  inherit (self.inputs.inclusive.lib) inclusive;

  inherit (self.inputs.nixpkgs-crystal.legacyPackages.${system}) crystal;

  pp = v: trace (toJSON v) v;

  inherit (self.inputs.bitte-cli.legacyPackages.${system}) bitte;

  devShell = final.callPackage ./pkgs/dev-shell.nix { };

  nixosModules = import ./pkgs/nixos-modules.nix { inherit nixpkgs lib; };

  sops-add = prev.callPackage ./pkgs/sops-add.nix { };

  clusters = final.callPackage ./lib/clusters.nix { inherit self system; } {
    root = ./clusters;
  };

  nixosConfigurations = lib.pipe final.clusters [
    (lib.mapAttrsToList (clusterName: cluster:
      lib.mapAttrsToList
      (name: value: lib.nameValuePair "${clusterName}-${name}" value)
      (cluster.nodes // cluster.groups // cluster.groups-ipxe)))
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

  ssh-keys = let
    authorized_keys = lib.fileContents ../modules/ssh_keys/authorized_keys;
    keys = import (ops-lib + "/overlays/ssh-keys.nix") lib;
    inherit (keys) allKeysFrom devOps;
  in { devOps = allKeysFrom devOps; };
}
