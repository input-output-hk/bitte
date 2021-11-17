{ nixpkgs
, bitte
}:

{ pkgs
  # Different mkSystem service levels:
  #  - While systems might share the foundations herein
  #  - Not all are customized with self, inputs, nodeName, etc.
  # This is no contradiction.
, self ? null
, inputs ? null
, modules ? null
, nodeName ? null
}:
let
  bitteSystem = specializationModule:
    nixpkgs.lib.nixosSystem {
      inherit pkgs;
      inherit (pkgs) system;
      modules = [ bitte.nixosModule specializationModule ] ++ modules;
      specialArgs = {
        inherit nodeName self inputs;
        inherit (bitte.inputs) terranix;
        bittelib = bitte.lib;
        terralib = bitte.lib.terralib;
      };
    };

  bitteProtoSystem = bitteSystem ({
    imports = [
      ../profiles/nix.nix
      ../profiles/consul/policies.nix
    ];
  });

  bitteAmazonSystem = bitteSystem ({ modulesPath, ... }: {
    imports = [ "${modulesPath}/../maintainers/scripts/ec2/amazon-image.nix" ];
  });
  bitteAmazonSystemBaseAMI = bitteSystem ({ modulesPath, ... }: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image.nix"
      ../../profiles/ami-base-config.nix
    ];
  });

  bitteAmazonZfsSystem = bitteSystem ({ modulesPath, ... }: {
    imports = [ "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix" ];
  });
  bitteAmazonZfsSystemBaseAMI = bitteSystem ({ modulesPath, ... }: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix"
      ../../profiles/ami-base-config.nix
    ];
  });

in
{
  inherit
    bitteSystem
    bitteProtoSystem
    bitteAmazonSystem
    bitteAmazonSystemBaseAMI
    bitteAmazonZfsSystem
    bitteAmazonZfsSystemBaseAMI
    ;
}
