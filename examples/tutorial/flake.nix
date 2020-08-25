{
  description = "My bitte testnet";

  # These inputs will pull bitte and some needed tools
  inputs = {
    bitte.url         = "github:input-output-hk/bitte";
    bitte-cli.follows = "bitte/bitte-cli";
    inclusive.url     = "github:manveru/nix-inclusive";
    nixpkgs.follows   = "bitte/nixpkgs";
    terranix.follows  = "bitte/terranix";
    utils.url         = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils, ... }: 
    # For each system supported by nixpkgs and built by hydra (see
    # https://github.com/numtide/flake-utils#defaultsystems---system)
    (utils.lib.eachDefaultSystem (system: rec {
      # Expose an overlay
      overlay = import ./overlay.nix { inherit system self; };
      
      # Expose nixpkgs with the overlay
      legacyPackages = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # ssm-session-manager-plugin for AWS CLI
        overlays = [ overlay ];
      };
      
      # Expose a development shell
      inherit (legacyPackages) devShell;
    }));
}
