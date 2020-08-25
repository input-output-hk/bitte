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

Let's create a test cluster:

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

### Getting started

    mkdir bitte-tutorial
    cd bitte-tutorial
    
Now, chances are you're not using a version of Nix that supports
flakes, so let's take a quick diversion and bootstrap an environment
with flakes support:
    
    vi shell.nix

    let
      inherit (builtins) readFile fromJSON;
      
      src = fetchTarball {
        # This is just a known "good enough" nixpkgs commit, we'll un-hardcode
        # this later
        url = "https://github.com/NixOS/nixpkgs/archive/b8c367a7bd05e3a514c2b057c09223c74804a21b.tar.gz";
      };
    in with import src {}; mkShell { buildInputs = [ nixFlakes ]; }
    
Then we can get back to initializing our project:

    nix-shell --run "nix flake init"
    
