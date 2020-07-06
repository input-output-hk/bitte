{ ... }: {
  imports = [ ./default.nix ];

  services.consul = { enable = true; };
}
