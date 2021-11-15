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
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image.nix"
      { ec2.efi = true; }
    ];
  });
  bitteAmazonSystemBaseAMI = bitteSystem ({ modulesPath, ... }: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image.nix"
      ../profiles/ami-base-config.nix
    ];
  });

  bitteAmazonZfsSystem = bitteSystem ({ modulesPath, ... }: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix"
      { ec2.efi = true; }
    ];
  });
  bitteAmazonZfsSystemBaseAMI = bitteSystem ({ modulesPath, ... }: {
    imports = [
      "${modulesPath}/../maintainers/scripts/ec2/amazon-image-zfs.nix"
      ../profiles/ami-base-config.nix
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
