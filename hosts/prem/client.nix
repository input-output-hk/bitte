{ self, pkgs, config, lib, ... }: {
  imports = [
    ../../profiles/prem/common.nix
    ../../profiles/prem/consul-client.nix
    ../../profiles/prem/docker.nix
    ../../profiles/prem/nomad-client.nix
    ../../profiles/prem/telegraf.nix
    ../../profiles/prem/vault-client.nix
    ../../profiles/prem/secrets.nix
    ../../profiles/prem/reaper.nix
    ../../profiles/prem/builder.nix
    ../../profiles/prem/zfs-client-options.nix
  ];

  services = {
    vault-agent-client.enable = true;
    vault.enable = lib.mkForce false;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-client";
    zfs-client-options.enable = true;
  };

  boot.cleanTmpDir = true;

  time.timeZone = "UTC";
  networking.firewall.enable = false;
}
