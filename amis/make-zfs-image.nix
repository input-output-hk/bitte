{ config, lib, pkgs, ... }:

with lib;

let
  name = "zfs-image";
  poolName = config.zfs.poolName;
  bootSize = 1024;
  diskSize = 1024 * 2;
  closureInfo = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel channelSources ]; };
  preVM = ''
    PATH=$PATH:${pkgs.qemu_kvm}/bin
    mkdir $out
    diskImage=nixos.raw
    qemu-img create -f qcow2 $diskImage ${toString diskSize}M
  '';
  postVM = ''
    qemu-img convert -f qcow2 -O vpc $diskImage $out/nixos.vhd
    ls -ltrhs $out/ $diskImage
    time sync $out/nixos.vhd
    ls -ltrhs $out/
  '';
  modulesTree = pkgs.aggregateModules (with config.boot.kernelPackages; [ kernel zfs ]);
  nixpkgs = lib.cleanSource pkgs.path;
  # FIXME: merge with channel.nix / make-channel.nix.
  channelSources = pkgs.runCommand "nixos-${config.system.nixos.version}" {} ''
    mkdir -p $out
    cp -prd ${nixpkgs} $out/nixos
    chmod -R u+w $out/nixos
    if [ ! -e $out/nixos/nixpkgs ]; then
      ln -s . $out/nixos/nixpkgs
    fi
    rm -rf $out/nixos/.git
    echo -n ${config.system.nixos.versionSuffix} > $out/nixos/.version-suffix
  '';
  image = (pkgs.vmTools.override {
    rootModules = [ "zfs" "9p" "9pnet_virtio" "virtio_pci" "virtio_blk" "rtc_cmos" ];
    kernel = modulesTree;
  }).runInLinuxVM (pkgs.runCommand name { inherit preVM postVM; } ''
    export PATH=${lib.makeBinPath (with pkgs; [ nix e2fsprogs zfs utillinux config.system.build.nixos-enter config.system.build.nixos-install ])}:$PATH

    cp -sv /dev/vda /dev/sda

    export NIX_STATE_DIR=$TMPDIR/state
    nix-store --load-db < ${closureInfo}/registration

    sfdisk /dev/vda <<EOF
    label: gpt
    device: /dev/vda
    unit: sectors
    1 : size=2048, type=21686148-6449-6E6F-744E-656564454649
    2 : size=${toString (bootSize*2048)}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
    3 : type=CA7D7CCB-63ED-4C53-861C-1742536059CC
    EOF

    mkfs.ext4 /dev/vda2 -L NIXOS_BOOT
    zpool create -o ashift=12 -o altroot=/mnt -o autoexpand=on ${poolName} /dev/vda3
    zfs create -o mountpoint=legacy ${poolName}/root
    zfs create -o mountpoint=legacy ${poolName}/home
    zfs create -o mountpoint=legacy ${poolName}/nix
    zfs create -o mountpoint=legacy ${poolName}/var
    mount -t zfs ${poolName}/root /mnt
    mkdir /mnt/{home,nix,boot,var}
    mount -t zfs ${poolName}/home /mnt/home
    mount -t zfs ${poolName}/nix /mnt/nix
    mount -t zfs ${poolName}/var /mnt/var
    mount -t ext4 /dev/vda2 /mnt/boot
    zfs set compression=lz4 ${poolName}/nix
    zfs set xattr=off ${poolName}/nix
    zfs set atime=off ${poolName}/nix
    echo copying toplevel
    time nix copy --no-check-sigs --to 'local?root=/mnt/' ${config.system.build.toplevel}
    ${lib.optionalString config.zfs.image.shipChannels ''
      echo copying channels
      time nix copy --no-check-sigs --to 'local?root=/mnt/' ${channelSources}
    ''}

    echo installing bootloader
    time nixos-install --root /mnt --no-root-passwd --system ${config.system.build.toplevel} ${lib.optionalString config.zfs.image.shipChannels "--channel ${channelSources}"} --substituters ""

    zfs inherit compression ${poolName}/nix
    df -h
    umount /mnt/{home,nix,boot,var,}
    zpool export ${poolName}
  '');
in {
  imports = [
    ./zfs-runtime.nix
    ./amazon-shell-init.nix
  ];
  options = {
    zfs.image = {
      shipChannels = mkOption {
        type = types.bool;
        default = false;
        description = "include a copy of nixpkgs in the ami";
      };
    };
    zfs.regions = mkOption {
      type = types.listOf types.str;
      default = [ "eu-west-1" ];
      description = "which regions config.system.build.uploadAmi will upload to";
    };
    zfs.bucket = mkOption {
      type = types.str;
      default = "iohk-amis";
      description = "bucket used to upload the ami";
    };
  };
  config = {
    boot = {
      blacklistedKernelModules = [ "nouveau" "xen_fbfront" ];
    };
    networking = {
      hostId = "9474d585";
    };
    environment.systemPackages = [ pkgs.cryptsetup ];
    system.build.zfsImage = image;
    system.build.uploadAmi = import ./upload-ami.nix {
      inherit pkgs;
      image = "${config.system.build.zfsImage}/nixos.vhd";
      regions = config.zfs.regions;
      bucket = config.zfs.bucket;
    };
  };
}
