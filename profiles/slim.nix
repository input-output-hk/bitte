{ config, pkgs, lib, ... }: {
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  documentation.info.enable = false;
  documentation.doc.enable = false;
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" "en_US/ISO-8859-1" ];

  programs.sysdig.enable = true;

  time.timeZone = "UTC";

  environment.systemPackages = with pkgs; [
    awscli
    bat
    bind
    di
    dnsutils
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
}
