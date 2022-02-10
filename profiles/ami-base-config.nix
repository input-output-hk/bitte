{ config, pkgs, ... }: {

  /* The base configuration of our
     generic client & code node AMIs
  */

  imports = [ ./slim.nix ];
  nix.binaryCaches = [ "https://hydra.iohk.io" ];
  nix.binaryCachePublicKeys =
    [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];

  nix.nixPath =
    [ "nixpkgs=${pkgs.path}" "nixos-config=/etc/nixos/configuration.nix" ];

  nix.extraOptions = ''
    experimental-features = nix-command flakes ca-references
  '';

  systemd.services.console-getty.enable = false;

  # Log everything to the serial console.
  services.journald.extraConfig = ''
    ForwardToConsole=yes
    MaxLevelConsole=debug
  '';

  # systemctl kexec can only be used on efi images
  # ec2.efi = true;
  amazonImage.sizeMB = 4096;
}
