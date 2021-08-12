{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [
    ../profiles/prem/common.nix
    ../profiles/prem/telegraf.nix
    ../profiles/prem/vault/server.nix
    ../profiles/prem/consul/server.nix
    ../profiles/prem/nomad/server.nix
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
