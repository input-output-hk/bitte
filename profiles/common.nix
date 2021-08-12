{ config, pkgs, lib, ... }: {
  imports = [
    ./consul/default.nix
    ./nix.nix
    ./promtail.nix
    ./ssh.nix
    ./vault/default.nix
  ];

  environment.systemPackages = with pkgs; [
    age
    awscli
    bat
    bind
    cfssl
    di
    fd
    file
    gitMinimal
    htop
    jq
    lsof
    ncdu
    openssl
    ripgrep
    sops
    tcpdump
    tmux
    tree
    vim
  ];

  documentation = {
    man.enable = false;
    nixos.enable = false;
    info.enable = false;
    doc.enable = false;
  };

  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" "en_US/ISO-8859-1" ];

  time.timeZone = "UTC";

  programs.sysdig.enable = true;

  services = {
    openntpd.enable = lib.mkDefault true;
    promtail.enable = lib.mkDefault true;
  };

  boot.cleanTmpDir = true;

  networking = {
    extraHosts = lib.concatStringsSep "\n"
      (lib.mapAttrsToList (name: instance: "${instance.privateIP} ${name}")
        config.cluster.instances);

    timeServers = lib.mkForce [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
      "2.nixos.pool.ntp.org"
      "3.nixos.pool.ntp.org"
    ];

    firewall = {
      allowPing = true;
      enable = false;
    };
  };
}
