{ self, pkgs, config, ... }: {
  imports = [
    ./common.nix
    ./docker.nix
    ./consul/client.nix
    ./vault/client.nix
    ./nomad/client.nix
  ];

  boot.cleanTmpDir = true;

  # TODO: put our CA cert here.
  security.pki.certificates = [ ];
  time.timeZone = "UTC";
  networking.firewall.enable = false;
  services.amazon-ssm-agent.enable = true;
  services.vault-agent-client.enable = true;
}
