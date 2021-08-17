{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [
    ./common.nix
    ./consul/server.nix
    ./nomad/server.nix
    ./telegraf.nix
    ./vault/server.nix
  ];

  age.secrets.nomad-encrypt.file = config.age.encryptedRoot
    + "/nomad/encrypt.age";

  services = {
    promtail.enable = lib.mkForce false;
    telegraf.enable = lib.mkForce false;

    consul.enable = lib.mkDefault true;
    consul.enableDebug = lib.mkDefault true;

    vault.enable = true;
    vault-agent-core.enable = true;

    # telegraf.extraConfig.global_tags.role = "consul-server";

    nomad.enable = true;
  } // (lib.optionalAttrs (nodeName == "core0") {
    nomad-acl.enable = true;
    consul-acl.enable = true;
    vault-acl.enable = true;
    nomad-namespaces.enable = true;
  });
}
