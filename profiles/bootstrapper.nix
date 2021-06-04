{ config, lib, ... }:
let
  inherit (builtins) attrNames;
  inherit (lib) listToAttrs imap1 nameValuePair;
  inherit (config) cluster;
  inherit (cluster) instances domain;
in {
  imports = [ ./bootstrap.nix ];

  services = {
    s3-upload.enable = lib.mkDefault true;
    consul-policies.enable = lib.mkDefault true;
    nomad-acl.enable = lib.mkDefault true;
    vault-acl.enable = lib.mkDefault true;
    nomad-namespaces.enable = lib.mkDefault true;
  };
}
