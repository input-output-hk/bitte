{ config, lib, ... }:
let
  inherit (builtins) attrNames;
  inherit (lib) listToAttrs imap1 nameValuePair;
  inherit (config) cluster;
  inherit (cluster) instances domain;
in {
  imports = [ ./bootstrap.nix ];

  services = {
    s3-upload.enable = true;
    consul-policies.enable = true;
    nomad-acl.enable = true;
    vault-acl.enable = true;
    nomad-namespaces.enable = true;
  };
}
