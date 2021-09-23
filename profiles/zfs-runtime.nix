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
  imports = [ "${self.inputs.nixpkgs}/nixos/maintainers/scripts/ec2/amazon-image-zfs.nix" ];
  config = {
    # default is sometimes too small for client configs
    amazonImage.sizeMB = 8192;

    boot = {
      # growPartition does not support zfs directly, so the above postDeviceCommands use what this puts into PATH
      loader.grub.device = lib.mkForce "/dev/sda";
      zfs.devNodes = "/dev/";
      kernelParams = [ "console=ttyS0" ];
      initrd = {
        availableKernelModules = [
          "virtio_pci"
          "virtio_blk"
          "xen-blkfront"
          "xen-netfront"
          "nvme"
          "ena"
        ];
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
    };
    networking = {
      hostName = lib.mkDefault "";
      # xen host on aws
      timeServers = [ "169.254.169.123" ];
    };
    services.udev.packages = [ pkgs.ec2-utils ];
    services.openssh = {
      enable = true;
      permitRootLogin = "prohibit-password";
    };
  };
}
