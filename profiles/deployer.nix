{ lib, pkgs, ... }: {
  imports = [ ./nix.nix ./ssh.nix ];

  disabledModules = [ "virtualisation/amazon-image.nix" ];

  environment = {
    systemPackages = with pkgs; [
      bat
      bind
      cfssl
      di
      fd
      file
      gitMinimal
      htop
      iptables
      jq
      (lib.lowPrio inetutils)
      lsof
      ncdu
      nettools
      openssl
      ripgrep
      sops
      tcpdump
      tmux
      tree
      vim
    ];
  };

  documentation.enable = true;

  documentation.nixos.enable = true;

  networking.firewall.allowPing = true;

  services.openntpd.enable = true;

  boot.cleanTmpDir = true;

  time.timeZone = "UTC";

  networking = {
    hostName = "deployer";
    timeServers = lib.mkForce [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
      "2.nixos.pool.ntp.org"
      "3.nixos.pool.ntp.org"
    ];
  };

  users.extraUsers = {
    root.initialHashedPassword = lib.mkForce null;
    nixos.initialHashedPassword = lib.mkForce null;
  };

  services.getty.helpLine = lib.mkForce "";
}
