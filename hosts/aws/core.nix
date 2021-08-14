{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [
    ../../profiles/aws/common.nix
    ../../profiles/aws/telegraf.nix
    ../../profiles/aws/vault/server.nix
    ../../profiles/aws/consul/server.nix
    ../../profiles/aws/nomad/server.nix
  ];

  services = {
    consul.enableDebug = false;
    consul.enable = true;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-server";
    vault-agent-core.enable = true;
    vault-consul-token.enable = true;
  };
}

