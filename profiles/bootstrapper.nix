{ config, lib, ... }: {
  imports = [ ./bootstrap.nix ];

  services = {
    s3-upload.enable = lib.mkDefault true;
    consul-acl.enable = lib.mkDefault true;
    nomad-acl.enable = lib.mkDefault true;
    vault-acl.enable = lib.mkDefault true;
    nomad-namespaces.enable = lib.mkDefault true;
  };
}
