{ self, pkgs, config, lib, ... }:

with lib;

let poolName = config.zfs.poolName;
in {
  options = {
    zfs.poolName = mkOption {
      type = types.str;
      default = "tank";
    };
  };

  imports = [
    ./zfs-client-options.nix
  ];
  config = {
    boot = {
      boot.supportedFilesystems = [ "zfs" ];
      zfs.devNodes = "/dev/";
      kernelParams = [ "console=ttyS0" ];
    };
    fileSystems = {
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
    networking = {
      hostName = lib.mkDefault "";
      # xen host on aws
      timeServers = [ "169.254.169.123" ];
    };

    services.zfs-client-options.enable = true;

    services.udev.packages = [ pkgs.ec2-utils ];
    services.openssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
  };
}
