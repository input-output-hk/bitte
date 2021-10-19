{ pkgs, lib, config, ... }:

with lib;

let
  cfg = config.bitte;
  poolName = config.zfs.poolName;
in {
  options.bitte.nixosAmiSeparateBootPartition = {
    enable = mkEnableOption "Use the new nixos 21.11 ami boot partition scheme";
  };

  config = mkIf cfg.nixosAmiSeparateBootPartition.enable {
    # nixos-21.11pre and after behavior
    boot.loader.grub.devices = lib.mkOverride 10 [ "/dev/xvda" ];

    fileSystems = lib.mkOverride 10 {
      "/" = {
        fsType = "zfs";
        device = "${poolName}/system/root";
      };
      "/home" = {
        fsType = "zfs";
        device = "${poolName}/user/home";
      };
      "/nix" = {
        fsType = "zfs";
        device = "${poolName}/local/nix";
      };
      "/var" = {
        fsType = "zfs";
        device = "${poolName}/system/var";
      };
      "/boot" = {
        fsType = "vfat";
        device = "/dev/disk/by-label/ESP";
      };
    };
  };

}
