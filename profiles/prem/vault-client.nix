{ ... }: {
  imports = [ ../vault/client.nix ];
  config.services.vault.enable = true;
}
