{ self, pkgs, lib, root }:
let
  inherit (builtins) attrNames readDir mapAttrs;
  inherit (lib)
    flip pipe mkForce filterAttrs flatten listToAttrs forEach nameValuePair
    mapAttrs';

  readDirRec = path:
    pipe path [
      readDir
      (filterAttrs (n: v: v == "directory" || n == "default.nix"))
      attrNames
      (map (name: path + "/${name}"))
      (map (child:
        if (baseNameOf child) == "default.nix" then
          child
        else
          readDirRec child))
      flatten
    ];

  mkSystem = nodeName: modules:
    lib.nixosSystem {
      # NOTE In the domain of possibilities that we currently care for, a NixOS
      # system would *always* be "x86_64-linux". In contrast, the *deployer* can
      # be at least x86_64-linux, x86_64-darwin, with Apple Silicon poised to
      # complicate things even further in the not-so-distant future.
      system = "x86_64-linux";
      pkgs = import self.inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [ self.overlay ];
      };
      modules = [
        ../modules/default.nix
        (self.inputs.nixpkgs + "/nixos/modules/virtualisation/amazon-image.nix")
      ] ++ modules;
      specialArgs = { inherit nodeName self; };
    };

  clusterFiles = readDirRec root;

in listToAttrs (forEach clusterFiles (file:
  let
    proto = lib.nixosSystem {
      system = "x86_64-linux";
      inherit pkgs;
      modules = [
        ../modules/default.nix
        ../profiles/nix.nix
        ../profiles/consul/policies.nix
        file
      ];
      specialArgs = { inherit self; };
    };

    tf = proto.config.tf;

    nodes = mapAttrs (name: instance:
      mkSystem name
      ([ { networking.hostName = mkForce name; } file ] ++ instance.modules))
      proto.config.cluster.instances;

    groups =
      mapAttrs (name: instance: mkSystem name ([ file ] ++ instance.modules))
      proto.config.cluster.autoscalingGroups;

    # All data used by the CLI should be exported here.
    topology = {
      nodes = flip mapAttrs proto.config.cluster.instances (name: node: {
        inherit (proto.config.cluster) kms region;
        inherit (node) name privateIP instanceType;
      });
      groups = attrNames groups;
    };

    bitte-secrets = pkgs.callPackage ../pkgs/bitte-secrets.nix {
      inherit (proto.config) cluster;
      bitte = pkgs.bitte.cli;
    };

    mkJob = import ./mk-job.nix proto;

  in nameValuePair proto.config.cluster.name ({
    inherit proto tf nodes groups topology bitte-secrets mkJob;
  } // bitte-secrets)))
