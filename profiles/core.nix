{ self, pkgs, config, ... }: {
  imports = [
    ./common.nix
    ./consul/server.nix
    ./haproxy.nix
    ./nginx.nix
    ./nomad/server.nix
    ./policies.nix
    ./vault/server.nix
  ];

  services.vault-agent-core.enable = true;

  # needed to scp the master token
  environment.etc."consul.d/.keep.json".text = "{}";

  environment.systemPackages = with pkgs; [ sops awscli cachix cfssl ];
}
