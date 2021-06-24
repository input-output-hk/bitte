{
  description = "Flake containing Bitte clusters";

  inputs = {
    nixpkgs.url =
      "github:NixOS/nixpkgs?rev=b8c367a7bd05e3a514c2b057c09223c74804a21b";
    nixpkgs-terraform.url = "github:input-output-hk/nixpkgs/iohk-terraform-2021-06";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-2105.url = "github:nixos/nixpkgs/nixos-21.05";
    utils.url = "github:kreisys/flake-utils";
    bitte-cli.url = "github:input-output-hk/bitte-cli";
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

  outputs = { self, hydra-provisioner, devshell, nixpkgs, utils, bitte-cli, nixpkgs-2105, ... }@inputs:
  let
    lib = import ./lib { inherit (nixpkgs) lib; };
  in utils.lib.simpleFlake rec {
    inherit lib nixpkgs;

    systems = [ "x86_64-linux" ];

    preOverlays = [ bitte-cli ];
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
    , nixos-rebuild
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

    nixosModules = let
      modules = lib.mkModules ./modules;
      default.imports = builtins.attrValues modules;
    in modules // { inherit default; };

  } // {
    profiles = lib.mkModules ./profiles;
  };
}
