{lib, ...}: {
  _file = ./physical-spec.nix;
  equinix = let
    legacyProperties = {
      properties = {
        mountpoint = "legacy";
      };
    };

    datasets = {
      "zpool/root" = legacyProperties;
      "zpool/nix" = legacyProperties;
      "zpool/home" = legacyProperties;
      "zpool/var" = legacyProperties;
      "zpool/cache" = legacyProperties;
      "zpool/nomad" = legacyProperties;
      "zpool/containers" = legacyProperties;
      "zpool/docker" = legacyProperties;
    };

    mounts = [
      {
        dataset = "zpool/root";
        point = "/";
      }
      {
        dataset = "zpool/nix";
        point = "/nix";
      }
      {
        dataset = "zpool/var";
        point = "/var";
      }
      {
        dataset = "zpool/cache";
        point = "/cache";
      }
      {
        dataset = "zpool/nomad";
        point = "/var/lib/nomad";
      }
      {
        dataset = "zpool/containers";
        point = "/var/lib/containers";
      }
      {
        dataset = "zpool/docker";
        point = "/var/lib/docker";
      }
      {
        dataset = "zpool/home";
        point = "/home";
      }
    ];
  in {
    "c3.small.x86" = {
      cpr_storage = {
        disks = [
          {
            device = "/dev/disk/by-packet-category/boot0";
            partitions = [
              {
                label = "BIOS";
                number = 1;
                size = "4096";
              }
              {
                label = "BOOT";
                number = 2;
                size = "512M";
              }
              {
                label = "SWAP";
                number = 3;
                size = "3993600";
              }
              {
                label = "ROOT";
                number = 4;
                size = 0;
              }
            ];
          }
        ];
        filesystems = [
          {
            mount = {
              device = "/dev/disk/by-packet-category/boot0-part2";
              format = "ext4";
              point = "/boot";
              create.options = ["-L" "BOOT"];
            };
          }
          {
            mount = {
              device = "/dev/disk/by-packet-category/boot0-part3";
              format = "swap";
              point = "none";
              create.options = ["-L" "SWAP"];
            };
          }
        ];
      };

      cpr_zfs = {
        inherit datasets mounts;
        pools = {
          zpool = {
            pool_properties = {};
            vdevs = [
              {
                disk = [
                  "/dev/disk/by-packet-category/boot1"
                  "/dev/disk/by-packet-category/boot0-part4"
                ];
              }
            ];
          };
        };
      };
    };

    "m3.small.x86" = {
      cpr_storage = {
        disks = [
          {
            device = "/dev/disk/by-packet-category/boot0";
            partitions = [
              {
                label = "BIOS";
                number = 1;
                size = "512M";
              }
              {
                label = "SWAP";
                number = 2;
                size = "3993600";
              }
              {
                label = "ROOT";
                number = 3;
                size = 0;
              }
            ];
          }
        ];
        filesystems = [
          {
            mount = {
              device = "/dev/disk/by-packet-category/boot0-part1";
              format = "vfat";
              point = "/boot";
              create.options = ["32" "-n" "EFI"];
            };
          }
          {
            mount = {
              device = "/dev/disk/by-packet-category/boot0-part2";
              format = "swap";
              point = "none";
              create.options = ["-L" "SWAP"];
            };
          }
        ];
      };

      cpr_zfs = {
        inherit datasets mounts;
        pools = {
          zpool = {
            pool_properties = {};
            vdevs = [
              {
                disk = [
                  "/dev/disk/by-packet-category/boot1"
                  "/dev/disk/by-packet-category/boot0-part3"
                ];
              }
            ];
          };
        };
      };
    };
  };
}
