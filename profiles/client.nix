{
  self,
  pkgs,
  config,
  lib,
  nodeName,
  ...
}: let
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
in {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./nomad/client.nix
    ./vault/client.nix
    ./glusterfs/client.nix

    ./auxiliaries/docker.nix
    ./auxiliaries/reaper.nix
  ];

  services.zfs-client-options.enable = deployType == "aws";

  services.telegraf.extraConfig.global_tags.role = "consul-client";

  boot.cleanTmpDir = true;

  time.timeZone = "UTC";

  # Maintain backward compat for the aws machines otherwise derive from hostname.
  # Also mkDefault, so machines which receive their own ZFS tied hostID during prov keep that.
  networking.hostId = if (deployType == "aws")
    then "9474d585"
    else
      (lib.mkDefault (lib.fileContents (pkgs.runCommand "hostId" {} ''
        ${pkgs.ruby}/bin/ruby -rzlib -e 'File.write(ENV["out"], "%08x" % Zlib.crc32("${nodeName}"))'
      '')));
}
