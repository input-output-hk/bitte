{ config, lib, ... }: {
  imports = [ ./bootstrap.nix ];

  services = {
    s3-upload.enable = true;
    consul-acl.enable = true;
    nomad-acl.enable = true;
    vault-acl.enable = true;
    nomad-namespaces.enable = true;
  };
}
