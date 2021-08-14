{ ... }:
let
  # Imported into all machines
  allModules = [
    ../modules/age.nix
    ../modules/allowed-uris.nix
    ../modules/consul.nix
    ../modules/consul-policies.nix
    ../modules/consul-template.nix
    ../modules/envoy.nix
    ../modules/hydra-declarative.nix
    ../modules/hydra-evaluator.nix
    ../modules/hydra.nix
    ../modules/ingress-config.nix
    ../modules/ingress.nix
    ../modules/nomad-autoscaler.nix
    ../modules/nomad-namespaces.nix
    ../modules/nomad.nix
    ../modules/nomad-policies.nix
    ../modules/s3-download.nix
    ../modules/s3-upload.nix
    ../modules/secrets.nix
    ../modules/telegraf.nix
    ../modules/terraform.nix
    ../modules/vault-agent-client.nix
    ../modules/vault-agent-server.nix
    ../modules/vault-backend.nix
    ../modules/vault.nix
    ../modules/vault-policies.nix
    ../modules/victoriametrics.nix
  ];

  mkClient = type: modules: modules ++ [ (./. + "/${type}/client.nix") ];
  mkCore = type: modules: modules ++ [ (./. + "/${type}/core.nix") ];

  mkHosts = type:
    let modules = allModules ++ [ (./. + "/${type}/default.nix") ];
    in {
      core = mkCore type modules;
      client = mkClient type modules;
    };

  prem = mkHosts "prem";
  aws = mkHosts "aws";
in { inherit prem aws; }
