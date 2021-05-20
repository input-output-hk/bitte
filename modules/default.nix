{ ... }: {
  imports = [
    ./amazon-ssm-agent.nix
    ./consul.nix
    ./consul-policies.nix
    ./consul-template.nix
    ./hydra
    ./ingress-config.nix
    ./ingress.nix
    ./nomad-autoscaler.nix
    ./nomad-namespaces.nix
    ./nomad.nix
    ./nomad-policies.nix
    ./promtail.nix
    ./s3-download.nix
    ./s3-upload.nix
    ./secrets.nix
    ./telegraf.nix
    ./terraform/clients.nix
    ./terraform/consul.nix
    ./terraform/core.nix
    ./terraform/iam.nix
    ./terraform/network.nix
    ./terraform.nix
    ./vault-agent-client.nix
    ./vault-agent-server.nix
    ./vault-backend.nix
    ./vault.nix
    ./vault-policies.nix
    ./victoriametrics.nix
  ];

  disabledModules = [
    "services/databases/victoriametrics.nix"
    "services/monitoring/telegraf.nix"
    "services/networking/consul.nix"
    "services/security/vault.nix"
  ];
}
