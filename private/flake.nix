{
  # private inputs are combined with inputs, but do not propagate to consumer lock files
  # they have the added benefit of being pulled lazily, which means they are not evaluated
  # by the consumer if they are not needed
  inputs = {
    utils.url = "flake-utils";

    nixpkgs-docker.url = "github:nixos/nixpkgs/ff691ed9ba21528c1b4e034f36a04027e4522c58";

    agenix-cli.url = "github:cole-h/agenix-cli";

    deploy.url = "github:input-output-hk/deploy-rs";
    deploy.inputs.fenix.follows = "fenix";

    terranix.url = "github:terranix/terranix";

    nomad-driver-nix.url = "github:input-output-hk/nomad-driver-nix";

    # DEPRECATED: will be replaces by cicero soon
    hydra.url = "github:kreisys/hydra/hydra-server-includes";
  };

  outputs = {
    std,
    agenix,
    ragenix,
    fenix,
    capsules,
    ...
  } @ inputs: {inherit inputs;};

  nixConfig.flake-registry = "https://raw.githubusercontent.com/input-output-hk/flake-registry/iog/flake-registry.json";
}
