{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    awscli
    bat
    bind
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
    tmux
    tree
    vim
    envoy
  ];
}
