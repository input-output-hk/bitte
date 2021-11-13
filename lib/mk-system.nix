{ nixpkgs
, bitte
}:

{ pkgs
, self ? null
, modules ? null
, nodeName ? null
}:
let
  bitteSystem = specializationModule:
    nixpkgs.lib.nixosSystem {
      inherit pkgs;
      inherit (pkgs) system;
      modules = [ bitte.nixosModule specializationModule ] ++ modules;
      specialArgs = { inherit nodeName self; };
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
      ../../profiles/ami-base.nix
    ];
  });

  bitteAmazonZfsSystem = bitteSystem ({ modulesPath, ... }: {
    imports = [ "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix" ];
  });
  bitteAmazonZfsSystemBaseAMI = bitteSystem ({ modulesPath, ... }: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix"
      ../../profiles/ami-base.nix
    ];
  });

in {
  inherit
    bitteSystem
    bitteProtoSystem
    bitteAmazonSystem
    bitteAmazonSystemBaseAMI
    bitteAmazonZfsSystem
    bitteAmazonZfsSystemBaseAMI
  ;
}
