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

    fileSystems = lib.mkForce {
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

    cluster.autoscalingGroups = lib.mapAttrs (region: value:
      config.cluster.autoscalingGroups."${region}" // {
        userData = ''
          #!/usr/bin/env bash
          export NIX_CONFIG="${nixConf}"

          nix shell nixpkgs#zfs -c zfs set com.sun:auto-snapshot=true tank/system
          nix shell nixpkgs#zfs -c zfs set atime=off tank/local/nix

          set -exuo pipefail
          pushd /run/keys
          nix shell nixpkgs#awscli -c aws s3 cp "s3://${cfg.s3Bucket}/infra/secrets/${cfg.name}/${cfg.kms}/source/source.tar.xz" source.tar.xz
          mkdir -p source
          tar xvf source.tar.xz -C source

          nix build ./source#nixosConfigurations.${cfg.name}-${this.config.name}.config.system.build.toplevel
          /run/current-system/sw/bin/nixos-rebuild --flake ./source#${cfg.name}-${this.config.name} switch &
          disown -a
        '';
      }) config.cluster.autoscalingGroups;
  };

}
