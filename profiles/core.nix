{ self, pkgs, config, ... }: {
  imports = [
    ./common.nix
    ./consul/server.nix
    ./haproxy.nix
    ./nomad/server.nix
    ./vault/server.nix
  ];

  services = {
    vault-agent-core.enable = true;
    ingress.enable = true;
  };

  environment.etc."consul.d/.keep.json".text = "{}";

  environment.systemPackages = with pkgs; [ sops awscli cachix cfssl ];
}
