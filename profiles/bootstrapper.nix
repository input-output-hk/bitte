{ config, lib, ... }: {
  imports = [ ./bootstrap.nix ];

  services = {
    consul-acl.enable = true;
    nomad-acl.enable = true;
    vault-acl.enable = true;
    nomad-namespaces.enable = true;
  };
}
