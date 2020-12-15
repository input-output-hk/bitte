{ config, pkgs, ... }: {
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  documentation.info.enable = false;
  documentation.doc.enable = false;
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" "en_US/ISO-8859-1" ];

  programs.sysdig.enable = true;

  environment.systemPackages = with pkgs; [
    bat
    bind
    di
    envoy
    fd
    file
    gitMinimal
    htop
    jq
    lsof
    ncdu
    nomad-autoscaler
    openssl
    ripgrep
    tcpdump
    tmux
    tree
    vim
  ];
}
