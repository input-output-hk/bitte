{ config, lib, pkgs, ... }: {
  imports = [
    ./consul/default.nix
    ./nix.nix
    ./promtail.nix
    ./ssh.nix
    ./vault/default.nix
  ];

  services = {
    amazon-ssm-agent.enable = true;
    vault.enable = true;
    consul.enable = true;
    openntpd.enable = true;
    fail2ban.enable = true;
  };

  fileSystems."/".device = lib.mkDefault "/dev/disk/by-label/nixos";
  boot.loader.grub.devices = lib.mkForce [ "/dev/nvme0n1" ];

  environment.variables = { AWS_DEFAULT_REGION = config.cluster.region; };

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = false;
  networking.timeServers = lib.mkForce [
    "0.nixos.pool.ntp.org"
    "1.nixos.pool.ntp.org"
    "2.nixos.pool.ntp.org"
    "3.nixos.pool.ntp.org"
  ];
  boot.cleanTmpDir = true;

  # remove after upgrading past 21.05
  users.users.ntp.group = "ntp";
  users.groups.ntp = {};
  users.groups.systemd-coredump = {};

  networking.firewall = let
    all = {
      from = 0;
      to = 65535;
    };
  in {
    enable = true;
    allowPing = true;
    allowedTCPPortRanges = [ all ];
    allowedUDPPortRanges = [ all ];
  };

  time.timeZone = "UTC";

  documentation.man.enable = false;
  documentation.nixos.enable = false;
  documentation.info.enable = false;
  documentation.doc.enable = false;
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" "en_US/ISO-8859-1" ];

  # Remove once nixpkgs is using openssh 8.7p1+ by default to avoid coredumps
  # Ref: https://bbs.archlinux.org/viewtopic.php?id=265221
  programs.ssh.package = pkgs.opensshNoCoredump;

  programs.sysdig.enable = true;

  environment.systemPackages = with pkgs; [
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
    tcpdump
    tmux
    tree
    vim
    vault-bin
    consul
    nomad
  ];

  networking.extraHosts = ''
    ${config.cluster.instances.core-1.privateIP} core.vault.service.consul
    ${config.cluster.instances.core-2.privateIP} core.vault.service.consul
    ${config.cluster.instances.core-3.privateIP} core.vault.service.consul

    ${lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: instance: "${instance.privateIP} ${name}")
      config.cluster.instances)}
  '';
}
