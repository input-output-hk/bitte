{ ... }: {
  imports = [ ./default.nix ];

  services.consul = {
    enable = true;
    addresses.http = lib.mkDefault "127.0.0.1";
  };
}
