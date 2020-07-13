{ ... }: {
  imports = [
    ./amazon-ssm-agent.nix
    ./consul.nix
    ./consul-policies.nix
    ./consul-template.nix
    ./nomad.nix
    ./policies.nix
    ./s3-download.nix
    ./terraform.nix
    ./terraform-output.nix
    ./vault-agent-client.nix
    ./vault-agent-server.nix
    ./vault.nix
  ];

  disabledModules =
    [ "services/security/vault.nix" "services/networking/consul.nix" ];
}
