{ self, pkgs, config, ... }: {
  imports = [
    ./common.nix
    ./consul/server.nix
    ./haproxy.nix
    ./nomad/server.nix
    ./telegraf.nix
    ./vault/server.nix
    ./secrets.nix
  ];

  services = {
    vault-agent-core.enable = true;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-server";
    vault-consul-token.enable = true;
    consul.enableDebug = true;
  };

  environment.systemPackages = with pkgs; [ sops awscli cachix cfssl ];
}
