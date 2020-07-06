{ ... }: {
  imports = [
    ./amazon-ssm-agent.nix
    ./certgen.nix
    ./consul.nix
    ./consul-policies.nix
    ./consul-template.nix
    ./nomad.nix
    ./policies.nix
    ./terraform.nix
    ./terraform-output.nix
    ./vault-agent.nix
    ./vault.nix
  ];

  disabledModules =
    [ "services/security/vault.nix" "services/networking/consul.nix" ];
}
