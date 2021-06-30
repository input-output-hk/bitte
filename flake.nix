{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
    nixpkgs-terraform.url = "github:input-output-hk/nixpkgs/iohk-terraform-2021-06";
    utils.url = "github:kreisys/flake-utils";
    bitte-cli.url = "github:input-output-hk/bitte-cli";
    hydra.url = "github:NixOS/hydra";
    hydra-provisioner.url = "github:input-output-hk/hydra-provisioner";
    ops-lib = {
      url = "github:input-output-hk/ops-lib";
      flake = false;
    };
    terranix = {
      url = "github:manveru/terranix/cleanup";
      flake = false;
    };
    nomad-source = {
      url = "github:input-output-hk/nomad/release-1.1.1";
      flake = false;
    };
    levant-source = {
      url =
        "github:hashicorp/levant?rev=05c6c36fdf24237af32a191d2b14756dbb2a4f24";
      flake = false;
    };
  };

  outputs = { self, hydra, hydra-provisioner, nixpkgs, utils, bitte-cli, ... }@inputs:
  let
    lib = import ./lib { inherit (nixpkgs) lib; };
  in utils.lib.simpleFlake rec {
    inherit lib nixpkgs;

    systems = [ "x86_64-linux" ];

    preOverlays = [ bitte-cli hydra-provisioner hydra ];
    overlay = import ./overlay.nix inputs;
    config.allowUnfree = true; # for ssm-session-manager-plugin

    shell = { devShell }: devShell;

    packages = {
      bitte
    , cfssl
    , consul
    , cue
    , glusterfs
    , grafana-loki
    , haproxy
    , haproxy-auth-request
    , haproxy-cors
    , nixFlakes
    , nomad
    , nomad-autoscaler
    , oauth2_proxy
    , sops
    , ssm-agent
    , terraform-with-plugins
    , vault-backend
    , vault-bin
    }@pkgs: pkgs;

    hydraJobs = packages;

    apps = { bitte }: {
      bitte = utils.lib.mkApp { drv = bitte; };
      defaultApp = utils.lib.mkApp { drv = bitte; };
    };

    nixosModules = (lib.mkModules ./modules) // {
      inherit (hydra.nixosModules) hydra;
      hydra-provisioner = hydra-provisioner.nixosModule;
    };

    # Nix supports both singular `nixosModule` and plural `nixosModules`
    # so I use the singular as a `defaultNixosModule` that won't spew a warning.
    nixosModule.imports = builtins.attrValues self.nixosModules;

    # Outputs that aren't directly supported by simpleFlake can go here
    # instead of having to doubleslash.
    extraOutputs = {
      profiles = lib.mkModules ./profiles;
    };
  };
}
