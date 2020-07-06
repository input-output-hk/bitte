{ ... }: {
  imports = [ ./bootstrap.nix ];

  services = {
    nginx.enable = true;
    vault-acl.enable = true;
    consul-policies.enable = true;
  };
}
