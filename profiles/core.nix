{
  self,
  pkgs,
  config,
  lib,
  nodeName,
  hashiTokens,
  ...
}: {
  imports = [
    ./common.nix
    ./consul/server.nix
    ./nomad/server.nix
    ./vault/server.nix
  ];

  services = {
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-server";
    ${hashiTokens.consul-vault-srv}.enable = true;
    consul.enableDebug = false;
  };

  environment.systemPackages = with pkgs; [sops awscli2 cfssl tcpdump rage];
}
