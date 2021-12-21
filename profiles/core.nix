{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [
    ./common.nix
    ./consul/server.nix
    ./nomad/server.nix
    ./vault/server.nix
  ];

  services = {
    vault-agent-core.enable = true;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-server";
    vault-consul-token.enable = true;
    consul.enableDebug = false;
  };

  environment.systemPackages = with pkgs; [ sops awscli cfssl tcpdump ];
}
