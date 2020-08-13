{ config, pkgs, ... }:
let
  bitte-secrets =
    pkgs.callPackage ../pkgs/bitte-secrets.nix { inherit (config) cluster; };
in {
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  documentation.info.enable = false;
  documentation.doc.enable = false;
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" "en_US/ISO-8859-1" ];

  programs.sysdig.enable = true;

  environment.systemPackages = with pkgs; [
    bat
    bind
    bitte-secrets.bitte-secrets-repair
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
    tmux
    tree
    vim
  ];
}
