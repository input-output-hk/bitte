{ ... }: {
  imports = [ ./default.nix ];
  config.services.vault.enable = false;
}
