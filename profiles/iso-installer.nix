{
  lib,
  pkgs,
  ...
}: {
  imports = [./auxiliaries/nix.nix ./auxiliaries/ssh.nix];

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
  boot.cleanTmpDir = true;
  time.timeZone = "UTC";

  services.chrony.enable = true;
  networking.hostName = lib.mkDefault "iso-installer";

  services.getty.helpLine = lib.mkForce ''
    Welcome to the bitte nixOS installer.
    1) Verify network connectivity (ex: ping 8.8.8.8)
    2) Follow instructions provided by devOps to proceed
    3) CAUTION: Running any install scripts will WIPE storage drives!
  '';
}
