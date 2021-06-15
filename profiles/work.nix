{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./nomad/client.nix
    ./telegraf.nix
    ./vault/client.nix
    ./secrets.nix
    ./reaper.nix
    ./builder.nix
    ./zfs-client-options.nix
  ];

  services = {
    vault-agent-client.enable = true;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-client";
    zfs-client-options.enable = true;
  };

  time.timeZone = "UTC";
  networking.firewall.enable = false;

  # Take our nodeName and generate a 32-bit host ID from it.
  networking.hostId = lib.fileContents (pkgs.runCommand "hostId" { } ''
    ${pkgs.ruby}/bin/ruby -rzlib -e 'File.write(ENV["out"], "%08x" % Zlib.crc32("${nodeName}"))'
  '');
}
