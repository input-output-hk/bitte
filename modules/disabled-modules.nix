{ ... }: {
  # NOTE Shouldn't these just go inside their respective modules?
  disabledModules = [
    "services/databases/victoriametrics.nix"
    "services/monitoring/telegraf.nix"
    "services/networking/consul.nix"
    "services/security/vault.nix"
  ];
}
