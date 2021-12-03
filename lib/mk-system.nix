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
  pkiFiles = {
    caCertFile = "/etc/ssl/certs/ca.pem";
    certChainFile = "/etc/ssl/certs/full.pem";
    certFile = "/etc/ssl/certs/cert.pem";
    keyFile = "/etc/ssl/certs/cert-key.pem";
  };

  bitteSystem = specializationModule:
    nixpkgs.lib.nixosSystem {
      inherit pkgs;
      inherit (pkgs) system;
      modules = [ bitte.nixosModule specializationModule ] ++ modules;
      specialArgs = {
        inherit nodeName self inputs pkiFiles;
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
