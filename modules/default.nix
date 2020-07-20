{ ... }: {
  imports = [
    ./amazon-ssm-agent.nix
    ./consul-policies.nix
    ./consul-template.nix
    ./consul.nix
    ./ingress.nix
    ./nomad-policies.nix
    ./nomad.nix
    ./s3-download.nix
    ./s3-upload.nix
    ./terraform-output.nix
    ./terraform.nix
    ./vault-agent-client.nix
    ./vault-agent-server.nix
    ./vault-policies.nix
    ./vault.nix
  ];

  disabledModules =
    [ "services/security/vault.nix" "services/networking/consul.nix" ];
}
