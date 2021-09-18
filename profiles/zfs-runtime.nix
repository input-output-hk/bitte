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
      growPartition = true;
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
        postDeviceCommands = lib.mkMerge [
          (lib.mkBefore ''
            echo all block devs:
            lsblk
            echo and all dev files
            ls -l /dev/
            if [ -e /dev/nvme0n1 ]; then
              ln -sv /dev/nvme0n1 /dev/sda
            fi
            echo resizing sda3
            TMPDIR=/run sh $(type -P growpart) "/dev/sda" "3"
            udevadm settle
          '')
          # zfs mounts within postDeviceCommands so mkBefore and mkAfter must be used
          (lib.mkAfter ''
            echo expanding pool...
            if [ -e /dev/nvme0n1p3 ]; then
              ln -sv /dev/nvme0n1p3 /dev/sda3
            fi
            zpool online -e ${poolName} sda3
            zpool online -e ${poolName} xvda3
            zpool online -e ${poolName} nvme0n1p3
          '')
        ];
        network.enable = true;
        postMountCommands = ''
          metaDir=$targetRoot/etc/ec2-metadata
          mkdir -m 0755 -p "$metaDir"

          echo "getting EC2 instance metadata..."

          if ! [ -e "$metaDir/ami-manifest-path" ]; then
            wget -q -O "$metaDir/ami-manifest-path" http://169.254.169.254/1.0/meta-data/ami-manifest-path
          fi

          if ! [ -e "$metaDir/user-data" ]; then
            wget -q -O "$metaDir/user-data" http://169.254.169.254/1.0/user-data && chmod 600 "$metaDir/user-data"
          fi

          if ! [ -e "$metaDir/hostname" ]; then
            wget -q -O "$metaDir/hostname" http://169.254.169.254/1.0/meta-data/hostname
          fi

          if ! [ -e "$metaDir/public-keys-0-openssh-key" ]; then
            wget -q -O "$metaDir/public-keys-0-openssh-key" http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key
          fi
        '';
      };
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
