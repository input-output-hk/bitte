{
  description = "Flake containing Bitte clusters";

  # --- Public Inputs --------
  # intended to defer locking to the consumer
  inputs = {
    nixpkgs.url = "nixos-21_11";
    nixpkgs-unstable.url = "nixpkgs-unstable";
    nix.url = "nix-2_10";

    ops-lib = {
      url = "ops-lib";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    nix,
    ...
  } @ pub: let
    inherit (inputs) std utils;

    priv = (import ./lib/call-flake.nix) {
      type = "path";
      path = ./private;
      # needs to be updated any time private inputs are touched
      narHash = "sha256-WpyvDOGanWmgh1bk/KF8L0SL/wkJq9oB6aswlIDtNRs=";
    } {};

    inputs = priv.inputs // pub;
  in
    inputs.std.growOn {
      inherit inputs;
      cellsFrom = ./nix;
      organelles = [
        (inputs.std.devshells "devshells")
        (inputs.std.installables "packages")

        # ----------
        # NixOS: Modules, Profiles, Aggregates
        # ----------

        # profile aggregates - combine profiles into classes
        #   "composition over case switches"
        (inputs.std.functions "aggregates")
        # profiles - have side effects; don't define options
        (inputs.std.functions "profiles")
        # modules - have no side effects; define options
        (inputs.std.functions "modules")

        # ----------
        # Terraform: loops
        # ----------

        # loops - reconcile a target state
        (inputs.std.functions "loops")
      ];
    }
    # soil -- TODO: remove soil
    (let
      overlays = [
        inputs.hydra.overlay
        # inputs.deploy.overlay
        localPkgsOverlay
        terraformProvidersOverlay
        (_: prev: {inherit (self.packages."${prev.system}") bitte;})
      ];
      terraformProvidersOverlay =
        import ./terraform-providers-overlay.nix inputs;
      localPkgsOverlay = import ./overlay.nix inputs;

      pkgsForSystem = system:
        import nixpkgs {
          inherit overlays system;
          config.allowUnfree = true; # for ssm-session-manager-plugin
        };

      unstablePkgsForSystem = system:
        import nixpkgs-unstable {
          inherit overlays system;
        };

      lib = import ./lib {
        inherit (nixpkgs) lib;
        inherit inputs;
      };
    in
      utils.lib.eachSystem [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ] (system: let
        legacyPackages = pkgsForSystem system;
        unstablePackages = unstablePkgsForSystem system;
      in rec {
        inherit legacyPackages;

        packages = {inherit (self.${system}.cli.packages) bitte;};
        defaultPackage = packages.bitte;

        hydraJobs = let
          constituents = {
            inherit
              (legacyPackages)
              bitte
              cfssl
              ci-env
              consul
              cue
              glusterfs
              grafana-loki
              haproxy
              haproxy-auth-request
              haproxy-cors
              nixFlakes
              nomad
              nomad-autoscaler
              oauth2-proxy
              sops
              terraform-with-plugins
              vault-backend
              vault-bin
              ;
          };
        in {
          inherit constituents;
          required = legacyPackages.mkRequired constituents;
        };
      })
      // {
        inherit lib;
        # eta reduce not possibe since flake check validates for "final" / "prev"
        overlay = nixpkgs.lib.composeManyExtensions overlays;
        profiles = lib.mkModules ./profiles;
        nixosModules =
          (lib.mkModules ./modules)
          // {
            # Until ready to update to the new age module options
            # agenix = ragenix.nixosModules.age;
          };
        nixosModule.imports = builtins.attrValues self.nixosModules;
        devshellModule = import ./devshellModule.nix;
      });

  nixConfig = {
    flake-registry = "https://raw.githubusercontent.com/input-output-hk/flake-registry/iog/flake-registry.json";

    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.iog.io"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
