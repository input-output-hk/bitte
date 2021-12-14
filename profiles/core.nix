{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [
    ./common.nix
    ./consul/server.nix
    ./nomad/server.nix
    ./telegraf.nix
    ./vault/server.nix
  ];

  age.secrets.nomad-encrypt.file = ../encrypted/nomad/encrypt.age;

  services = {
    promtail.enable = lib.mkForce false;
    telegraf.enable = lib.mkForce false;

    vault-agent-core.enable = true;
    # nomad.enable = true;
    # telegraf.extraConfig.global_tags.role = "consul-server";
    # vault-consul-token.enable = true;

    nomad.enable = lib.mkForce true;
    consul.enableDebug = lib.mkDefault false;

    consul-acl.enable = nodeName == "core0";
    vault-acl.enable = nodeName == "core0";
  };

  environment.systemPackages = with pkgs; [ sops awscli cfssl tcpdump ];
}
