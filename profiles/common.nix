{ config, lib, pkgs, ... }:
let
  inherit (config.cluster) nodes coreNodes premNodes premSimNodes;
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
in {

  imports = [
    ./slim.nix

    ./auxiliaries/secrets.nix
    ./auxiliaries/nix.nix
    ./auxiliaries/ssh.nix
    ./auxiliaries/promtail.nix
    ./auxiliaries/telegraf.nix
    ./auxiliaries/builder.nix
  ];

  # avoid CVE-2021-4034 (PwnKit)
  security.polkit.enable = false;

  services.ssm-agent.enable = deployType == "aws";

  # Chrony succeeds in quickly syncing large time drift systems,
  # whereas openntpd may stay unsynced for extended periods.
  services.chrony.enable = true;

  # Ensure that the timeservers are able to resolve before iburst probing
  systemd.services.chronyd.after = lib.mkIf config.services.dnsmasq.enable [ "dnsmasq.service" ];

  networking.timeServers = lib.mkForce [
    "0.nixos.pool.ntp.org"
    "1.nixos.pool.ntp.org"
    "2.nixos.pool.ntp.org"
    "3.nixos.pool.ntp.org"
  ];

  services.fail2ban.enable = deployType != "premSim";

  environment.variables = {
    AWS_DEFAULT_REGION = lib.mkIf (deployType != "prem") config.cluster.region;
  };
  environment.systemPackages = with pkgs; [ consul nomad vault-bin ];

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = false;

  boot.cleanTmpDir = true;

  networking.firewall = let
    all = {
      from = 0;
      to = 65535;
    };
  in {
    enable = true;
    allowPing = true;

    # TODO: deprecate open firewall with SG dependency in aws
    allowedTCPPortRanges = lib.mkIf (deployType == "aws") [ all ];
    allowedUDPPortRanges = lib.mkIf (deployType == "aws") [ all ];
  };

  # Remove once nixpkgs is using openssh 8.7p1+ by default to avoid coredumps
  # Ref: https://bbs.archlinux.org/viewtopic.php?id=265221
  programs.ssh.package = pkgs.opensshNoCoredump;

  networking.extraHosts = let
    inherit (config.services.vault) serverNodeNames;
  in ''
    ${lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: instance: "${instance.privateIP} ${name}.internal")
      (lib.filterAttrs (k: v: lib.elem k serverNodeNames) nodes))}

    ${lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: instance: "${instance.privateIP} ${name}")
      (if deployType != "premSim" then (coreNodes // premNodes) else premSimNodes))}
  '';
}
