{ self, pkgs, config, ... }: {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./docker.nix
    ./nomad/client.nix
    ./telegraf.nix
    ./vault/client.nix
  ];

  services = {
    amazon-ssm-agent.enable = true;
    vault-agent-client.enable = true;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-client";
  };

  boot.cleanTmpDir = true;

  # TODO: put our CA cert here.
  security.pki.certificates = [ ];
  time.timeZone = "UTC";
  networking.firewall.enable = false;
}
