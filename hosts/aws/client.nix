{ ... }: {
  disabledModules = [ "virtualisation/amazon-image.nix" ];
  networking = { hostId = "9474d585"; };
  boot.loader.grub.device = lib.mkForce "/dev/nvme0n1";
}
