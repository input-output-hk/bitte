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

  imports = [ ./zfs-client-options.nix ];
  config = {
    boot = {
      initrd.supportedFilesystems = [ "zfs" ];
      supportedFilesystems = [ "zfs" ];
      zfs.devNodes = "/dev/";
      kernelParams = [ "console=ttyS0" ];
    };

    fileSystems = mkForce {
      "/" = {
        fsType = "zfs";
        device = "${poolName}/root";
      };
      "/home" = {
        fsType = "zfs";
        device = "${poolName}/home";
      };
      "/nix" = {
        fsType = "zfs";
        device = "${poolName}/nix";
      };
      "/var" = {
        fsType = "zfs";
        device = "${poolName}/var";
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
