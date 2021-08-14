{ ... }: {
  imports = [ ./consul.nix ];

  services.consul = { enable = true; };
}
