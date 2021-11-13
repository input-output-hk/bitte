{ config, lib, pkgs, ... }: {
  imports = [
    ./consul/default.nix
    ./nix.nix
    ./promtail.nix
    ./slim.nix
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

  environment.variables = { AWS_DEFAULT_REGION = config.cluster.region; };
  environment.systemPackages = with pkgs; [ consul nomad vault-bin ];

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
  users.groups.ntp = { };
  users.groups.systemd-coredump = { };

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

  # Remove once nixpkgs is using openssh 8.7p1+ by default to avoid coredumps
  # Ref: https://bbs.archlinux.org/viewtopic.php?id=265221
  programs.ssh.package = pkgs.opensshNoCoredump;

  networking.extraHosts = ''
    ${config.cluster.instances.core-1.privateIP} core.vault.service.consul
    ${config.cluster.instances.core-2.privateIP} core.vault.service.consul
    ${config.cluster.instances.core-3.privateIP} core.vault.service.consul

    ${lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: instance: "${instance.privateIP} ${name}")
      config.cluster.instances)}
  '';
}
