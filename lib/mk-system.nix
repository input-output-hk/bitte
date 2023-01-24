{
  nixpkgs,
  bitte,
}: {
  pkgs,
  # Different mkSystem service levels:
  #  - While systems might share the foundations herein
  #  - Not all are customized with self, inputs, nodeName, etc.
  # This is no contradiction.
  self ? null,
  inputs ? null,
  modules ? [],
  nodeName,
}: let
  bitteSystem = specializationModule: let
    res = nixpkgs.lib.nixosSystem {
      inherit pkgs;
      inherit (pkgs) system;
      modules =
        [
          ./mk-system/constants-module.nix
          ./mk-system/show-warnings-and-assertions-module.nix
          {imports = builtins.attrValues bitte.nixosModules;}
          specializationModule
        ]
        ++ modules;
      specialArgs = {
        inherit nodeName self inputs;
        inherit (bitte.inputs) terranix nomad-follower;
        bittelib = bitte.lib;
        inherit (bitte.lib) terralib;
      };
    };
  in
    builtins.seq res.config.showWarningsAndAssertions res;

  bitteProtoSystem = bitteSystem {
    imports = [
      ../profiles/auxiliaries/nix.nix
      ../profiles/consul/policies.nix
      # This module exists to appease failing assertions on evaluating
      # the proto system. The protosystem is only used to obtain the tf config.
      ({
        lib,
        config,
        ...
      }: {
        # assertion: The ‘fileSystems’ option does not specify your root file system.
        fileSystems."/" =
          lib.mkDefault {device = "/dev/disk/by-label/nixos";};

        # assertion: You must set the option ‘boot.loader.grub.devices’ or 'boot.loader.grub.mirroredBoots' to make the system bootable.
        boot.loader.grub.enable = lib.mkDefault false;

        # Set the default state version to avoid multiple warning traces for all proto evaluations
        system.stateVersion = lib.mkDefault "22.11";
      })
    ];
  };

  bitteAmazonSystem = bitteSystem ({modulesPath, ...}: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image.nix"
    ];
  });

  bitteAmazonSystemBaseAMI = bitteSystem ({modulesPath, ...}: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image.nix"
      ../profiles/ami-base-config.nix
    ];
  });

  bitteAmazonZfsSystem = bitteSystem ({modulesPath, ...}: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix"
    ];
  });

  bitteAmazonZfsSystemBaseAMI = bitteSystem ({modulesPath, ...}: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix"
      ../profiles/ami-base-config.nix
    ];
  });

  bittePremSystem = bitteSystem ({modulesPath, ...}: {
    imports = [
      ({
        lib,
        config,
        ...
      }: {
        # Required for initialization of equinix metal resources prior to the initial provisioning profile being obtained.
        fileSystems."/" = lib.mkDefault {device = "/dev/disk/by-label/nixos";};
        boot.loader.grub.enable = lib.mkDefault false;
      })
    ];
  });
in {
  inherit
    bitteSystem
    bittePremSystem
    bitteProtoSystem
    bitteAmazonSystem
    bitteAmazonSystemBaseAMI
    bitteAmazonZfsSystem
    bitteAmazonZfsSystemBaseAMI
    ;
}
