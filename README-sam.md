# Bitte

Schedule jobs to be run across compute fleets.

## Overview

Bitte is a tool designed to provision and deploy "compute fleets": a
cluster of machines that we can run abstract workloads on.

It was created to address the lack of fleet support in NixOps. NixOps
works in terms of individual machines, and doesn't support the more
abstract idea of "pools of machines".

A cluster consists of core nodes and a number of machines in
auto-scaling groups spread across regions and availability zones (we
call these "client" or "worker" machines).

The core nodes facilitate communication between the user and the
client machines, as well as between the client machines themselves.
Users submit jobs to the core nodes, and the core nodes decide how
that workload is spread across the client machines. The client
machines use the core nodes to facilitate service discovery,
distributed storage, etc.

## Implementation

The project is currently implemented using the following stack:

* [Nix](https://nixos.org/)
* [Hashicorp Terraform](https://www.terraform.io/)
* [Hashicorp Consul](https://www.consul.io)
* [Hashicorp Vault](https://www.vaultproject.io/)
* [Hashicorp Nomad](https://www.nomadproject.io/)
* [Grafana](https://grafana.com/)
* [Promtail](https://grafana.com/docs/loki/latest/clients/promtail/)
* [VictoriaMetrics](https://victoriametrics.com/)
* [HAProxy](https://www.haproxy.org/)

### Provisioning

We start by describing clusters in Nix. A typical cluster description
might look something like this:

    { ... }:
    {
      imports = [ ... ];
    
      cluster = {
        name = "my-testnet";

        # Core machines
        instances = {
          core-1 = {
            ...
          };
    
          core-2 = {
            ...
          };
    
          core-3 = {
            ...
          };
    
          monitoring = {
            ...
          };
        };

        # Client machines
        autoscalingGroups = {
          ...
        };

      };
    }

Nix builds this description to produce JSON Terraform configuration.
The [bitte-cli](https://github.com/input-output-hk/bitte-cli) tool
then applies this Terraform configuration to provision the cluster.

### Configuration

NixOS is used to configure each provisioned machine, much in the same
way as NixOps.

### Running

Nomad is a workload orchestrator, we use it to run our jobs across the
fleet of client machines.

Vault is a secrets management tool used to 

Consul is responsible for simple distributed KV storage, service
discovery, and service mesh communication. In particular we use Consul
Connect to facilitate inter-job communication in Nomad, Consul DNS for
discovery, and Consul KV for Vault.

The core machines run server instances of Consul, Vault, and Nomad.
The client machines run the Nomad jobs.

## Tutorial

Let's create a test cluster.

### Prerequisites

First you'll need to have [Nix](https://nixos.org/) installed.
We're using an experimental feature called `flakes` which increases speed of
development and deployment drastically, but still requires a bit of preparation.

To enable flake support, add the following line to `~/.config/nix/nix.conf`:

    experimental-features = nix-command flakes

From [Tweag](https://www.tweag.io/blog/2020-05-25-flakes):

  > A flake is simply a source tree (such as a Git repository)
  > containing a file named `flake.nix` that provides a standardized
  > interface to Nix artifacts such as packages or NixOS modules.

Although it is optional, you'll probably also want to add our binary
cache to `~/.config/nix/nix.conf`:

    substituters = https://manveru.cachix.org
    trusted-public-keys = manveru.cachix.org-1:L5nJHSinfA2K5dDCG3KAEadwf/e3qqhuBr7yCwSksXo=

### Getting started

#### Setup

    mkdir bitte-tutorial
    cd bitte-tutorial
    git init
    
Now, chances are you're not using a version of Nix that supports
flakes, so let's indulge a quick diversion and bootstrap an environment
with flakes support:
    
    vi shell.nix

    let
      src = fetchTarball {
        # This is just a known "good enough" nixpkgs commit, we'll un-hardcode
        # this later
        url = "https://github.com/NixOS/nixpkgs/archive/b8c367a7bd05e3a514c2b057c09223c74804a21b.tar.gz";
      };
    in with import src {}; mkShell { buildInputs = [ nixFlakes ]; }
    
Then we can get back to initializing our project:

    nix-shell --run "nix flake init"

This will create a `flake.nix` file that we should edit to look like
this:

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

The `overlay.nix` should like this:
  
    { system, self }:
    final: prev: {
      # Bitte itself
      bitte = let
        bitte-nixpkgs = import self.inputs.nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              vault-bin = self.inputs.bitte.legacyPackages.${system}.vault-bin;
            })
            self.inputs.bitte-cli.overlay.${system}
          ];
        };
      in bitte-nixpkgs.bitte;
    
      # Tools needed for development
      devShell = prev.mkShell {
        LOG_LEVEL = "debug";
    
        buildInputs = [
          final.bitte
          final.terraform-with-plugins
          prev.sops
          final.vault-bin
          final.glibc
          final.gawk
          final.openssl
          final.cfssl
        ];
      };

      inherit (self.inputs.bitte.legacyPackages.${system})
        vault-bin terraform-with-plugins;
    }

We then need to add these files to git. Nix flakes don't recognize
files outside of version control (for reproducibility reasons):

    git add flake.nix overlay.nix shell.nix

We can then enter a development shell:

    nix-shell --run "nix develop"

This command bootstraps us into an environment that has flake support,
then runs `nix develop` which will find the `devShell` output listed
in our `flake.nix` and enter a development shell. If you're already in
an environment with flake support, you can just run `nix develop`.

You should now be able to run `bitte`!

    bitte --help

Attempting to build any output of a flake (which we did when we
entered the development shell) will also generate a `flake.lock` lock
file. We can use this lock file to un-hardcode our `shell.nix`:

    let
      inherit (builtins) readFile fromJSON;
    
      lock = fromJSON (readFile ./flake.lock);
      pkgsInfo = lock.nodes.nixpkgs.locked;
      src = fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/${pkgsInfo.rev}.tar.gz";
      };
    in with import src {}; mkShell { buildInputs = [ nixFlakes ]; }

This change just pulls the version of Nixpkgs specified in our lock
file.

#### AWS

Next we'll need to setup our AWS environment. Firstly, we need to
configure the credentials and profile for our AWS user:

    cat ~/.aws/config
    [profile bitte]
    region = ap-southeast-2

    cat ~/.aws/credentials
    [bitte]
    aws_access_key_id=XXXXXXXXXXXXXXXXXXXX
    aws_secret_access_key=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

Finally, for convenience we'll want to setup a few environment
variables. `direnv` is recommended.

    vi .envrc
    
    export BITTE_CLUSTER=testnet
    export AWS_PROFILE=bitte
    export AWS_DEFAULT_REGION=ap-southeast-2
    export LOG_LEVEL=debug
    
#### Building a cluster

Let's build ourselves an example cluster: 

    mkdir -p clusters/testnet
    vi clusters/testnet/default.nix
    
    { self, lib, pkgs, config, ... }:
    {
      cluster = {
        name = "testnet";
        domain = "bitte-tutorial.iohkdev.io";
        
        flakePath = ../..;
        
        instances = {
          core-1 = {
            instanceType = "t2.small";
            privateIP = "172.16.0.10";
          };

          securityGroupRules = let
            vpcs = pkgs.terralib.vpcs config.cluster;
          
            global = [ "0.0.0.0/0" ];
            internal = [ config.cluster.vpc.cidr ]
              ++ (lib.flip lib.mapAttrsToList vpcs (region: vpc: vpc.cidr_block));
          in {
            internet = {
              type = "egress";
              port = 0;
              protocols = [ "-1" ];
              cidrs = global;
            };
  
            internal = {
              type = "ingress";
              port = 0;
              protocols = [ "-1" ];
              cidrs = internal;
            };
            
            ssh = {
              port = 22;
              cidrs = global;
            };
          };
        };   
      };
    }
    
`mkClusters` is a Nix function exposed by bitte. It reads all
`default.nix` files in the given `root` directory recursively. From
each of these files it creates a cluster configuration.

We'll need to add the following attributes to our overlay:

    vi overlay.nix
    
    {
      ...

      nixosConfigurations =
        self.inputs.bitte.legacyPackages.${system}.mkNixosConfigurations
        final.clusters;
    
      clusters = self.inputs.bitte.legacyPackages.${system}.mkClusters {
        root = ./clusters;
        inherit self system;
      };
    }

and the following outputs to our flake:

    vi flake.nix
    
    {
      description = "My bitte testnet";
    
      ... 

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
        })) // (let
          pkgs = import nixpkgs {
            overlays = [ self.overlay.x86_64-linux ];
            system = "x86_64-linux";
          };
        in { inherit (pkgs) nixosConfigurations clusters; });
    }
