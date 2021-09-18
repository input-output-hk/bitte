{
  description = "Bitte Nomad Example";

  inputs = {
    bitte.url = "github:input-output-hk/bitte/ami-wip";
    nixpkgs.follows = "bitte/nixpkgs";
  };

  outputs = { self, nixpkgs, bitte, ... }@inputs:
    bitte.lib.simpleFlake {
      inherit nixpkgs;
      systems = [ "x86_64-linux" ];

      preOverlays = [ bitte.overlay ];

      overlay = import ./overlay.nix inputs;

      packages = { }@pkgs: pkgs;

      devShell = { bitteShellCompat, cue }:
        bitteShellCompat {
          inherit self;
          extraPackages = [ cue ];
          cluster = "example-cluster";
          profile = "changeme";
          region = self.clusters."example-cluster".proto.config.cluster.region;
          domain = "changeme.example.com";
        };

      extraOutputs = let hashiStack = bitte.lib.mkHashiStack {
        flake = self;
        domain = "changeme.example.com";
      };
      in { inherit (hashiStack) clusters nixosConfigurations consulTemplates; };

      hydraJobs = { }@jobs:
        jobs // (builtins.mapAttrs (_: v: v.config.system.build.toplevel)
          self.nixosConfigurations);
    };
}
