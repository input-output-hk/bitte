{ nixpkgs, bitte }:

{ pkgs
# Different mkSystem service levels:
#  - While systems might share the foundations herein
#  - Not all are customized with self, inputs, nodeName, etc.
# This is no contradiction.
, self ? null, inputs ? null, modules ? [ ], nodeName ? null }:
let
  pkiFiles = {
    caCertFile = "/etc/ssl/certs/ca.pem";
    certChainFile = "/etc/ssl/certs/full.pem";
    certFile = "/etc/ssl/certs/cert.pem";
    keyFile = "/etc/ssl/certs/cert-key.pem";
  };

  hashiTokens = {
    vault = "/run/keys/vault-token";
    consul-default = "/run/keys/consul-default-token";
    consul-nomad = "/run/keys/consul-nomad-token";
    nomad-snapshot = "/run/keys/nomad-snapshot-token";
    nomad-autoscaler = "/run/keys/nomad-autoscaler-token";
  };

  showWarningsAndAssertions = { lib, config, ... }:
    let
      failedAssertions =
        map (x: x.message) (lib.filter (x: !x.assertion) config.assertions);
      validateConfig = if failedAssertions != [ ] then
        throw ''

          Failed assertions:
          ${builtins.concatStringsSep "\n"
          (map (x: "- ${x}") failedAssertions)}''
      else
        lib.showWarnings config.warnings;
    in {
      options.showWarningsAndAssertions = lib.mkOption {
        type = with lib.types; bool;
        default = validateConfig true;
      };
    };

  bitteSystem = specializationModule:
    let
      res = nixpkgs.lib.nixosSystem {
        inherit pkgs;
        inherit (pkgs) system;
        modules =
          [ showWarningsAndAssertions bitte.nixosModule specializationModule ]
          ++ modules;
        specialArgs = {
          inherit nodeName self inputs pkiFiles hashiTokens;
          inherit (bitte.inputs) terranix;
          bittelib = bitte.lib;
          inherit (bitte.lib) terralib;
        };
      };
    in builtins.seq res.config.showWarningsAndAssertions res;

  bitteProtoSystem = bitteSystem {
    imports = [
      ../profiles/auxiliaries/nix.nix
      ../profiles/consul/policies.nix
      # This module purely exists to appease failing assertions on evaluating
      # the proto system. The protosystem is only used to obtaion the tf config.
      ({ lib, ... }: {
        # assertion: The ‘fileSystems’ option does not specify your root file system.
        fileSystems."/" =
          lib.mkDefault { device = "/dev/disk/by-label/nixos"; };
        # assertion: You must set the option ‘boot.loader.grub.devices’ or 'boot.loader.grub.mirroredBoots' to make the system bootable.
        boot.loader.grub.enable = lib.mkDefault false;
      })
    ];
  };

  bitteAmazonSystem = bitteSystem ({ modulesPath, ... }: {
    imports = [ "${modulesPath}/../maintainers/scripts/ec2/amazon-image.nix" ];
  });
  bitteAmazonSystemBaseAMI = bitteSystem ({ modulesPath, ... }: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image.nix"
      ../profiles/ami-base-config.nix
    ];
  });

  bitteAmazonZfsSystem = bitteSystem ({ modulesPath, ... }: {
    imports =
      [ "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix" ];
  });
  bitteAmazonZfsSystemBaseAMI = bitteSystem ({ modulesPath, ... }: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix"
      ../profiles/ami-base-config.nix
    ];
  });

in {
  inherit bitteSystem bitteProtoSystem bitteAmazonSystem
    bitteAmazonSystemBaseAMI bitteAmazonZfsSystem bitteAmazonZfsSystemBaseAMI;
}
