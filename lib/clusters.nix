{ self, pkgs, system, lib, ... }:
{ root }:
let
  inherit (builtins) attrNames readDir mapAttrs;
  inherit (lib)
    flip pipe mkForce filterAttrs flatten listToAttrs forEach nameValuePair
    mapAttrs';

  readDirRec = path:
    pipe path [
      readDir
      (filterAttrs (n: v: v == "directory" || n == "default.nix"))
      attrNames
      (map (name: path + "/${name}"))
      (map (child:
        if (baseNameOf child) == "default.nix" then
          child
        else
          readDirRec child))
      flatten
    ];

  mkSystem = nodeName: modules:
    self.inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs system;
      modules = [
        { networking = { hostName = mkForce nodeName; }; }
        ../modules/default.nix
        self.nixosModules.amazon-image
      ] ++ modules;
      specialArgs = { inherit nodeName self; };
    };

  clusterFiles = readDirRec root;

in listToAttrs (forEach clusterFiles (file:
  let
    proto = self.inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs system;
      modules = [ ../modules/default.nix ../profiles/nix.nix file ];
      specialArgs = { inherit self; };
    };

    terraform-output = proto.config.terraform-output;
    terraform = proto.config.terraform;

    nodes =
      mapAttrs (name: instance: mkSystem name ([ file ] ++ instance.modules))
      proto.config.cluster.instances;

    groups =
      mapAttrs (name: instance: mkSystem name ([ file ] ++ instance.modules))
      proto.config.cluster.autoscalingGroups;

    groups-ipxe = mapAttrs' (name: instance:
      nameValuePair "${name}-ipxe" (mkSystem name ([
        (self.inputs.netboot + "/quickly.nix")
        {
          systemd.services.installer = {
            wantedBy = [ "multi-user.target" ];
            after = [ "network-onnline.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RestartSec = "30s";
              Restart = "on-failure";
            };

            path = with pkgs; [
              e2fsprogs
              coreutils
              proto.config.system.build.nixos-install
              proto.config.system.build.nixos-enter
              utillinux
              systemd
              nixFlakes
              dosfstools
              parted
              (writeShellScriptBin "install-from-ipxe" ''
                parted --script /dev/xvda -- mklabel msdos mkpart primary ext4 1MiB -1
                parted --script /dev/xvda -- mklabel gpt mkpart ESP fat32 8MiB 256MiB set 1 boot on mkpart primary ext4 256MiB -1

                mkdir -p /mnt
                mkfs.ext4 -F -L nixos /dev/xvda2
                mount /dev/xvda2 /mnt

                mkdir -p /mnt/boot
                mkfs.vfat -n ESP /dev/xvda1
                mount /dev/xvda1 /mnt/boot

                nix build "${self.outPath}#clusters.${proto.config.cluster.name}.groups.${name}.config.system.build.toplevel" -o /root/system
                nixos-install --system /root/system --root /mnt --no-root-passwd
              '')
            ];

            script = ''
              install-from-ipxe
              # systemctl reboot
            '';
          };

          systemd.services.amazon-init.enable = false;
          time.timeZone = "UTC";
        }
        {
          fileSystems."/" = mkForce {
            fsType = "tmpfs";
            options = [ "mode=0755" ];
          };
        }
        file
        ../profiles/ssh.nix
        ../profiles/nix.nix
        ../profiles/slim.nix
      ]))) proto.config.cluster.autoscalingGroups;

    # All data used by the CLI should be exported here.
    topology = {
      nodes = flip mapAttrs proto.config.cluster.instances (name: node: {
        inherit (proto.config.cluster) kms region;
        inherit (node) name privateIP instanceType;
      });
      groups = attrNames groups;
    };

  in nameValuePair proto.config.cluster.name {
    inherit proto terraform-output terraform nodes groups groups-ipxe topology;
  }))
