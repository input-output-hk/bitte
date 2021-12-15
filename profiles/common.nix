{ config, pkgs, lib, self, nodeName, ... }: {
  imports = [
    ../modules
    ./consul/default.nix
    ./consul/policies.nix
    ./nix.nix
    ./promtail.nix
    ./ssh.nix
  ];

  disabledModules = [ "virtualisation/amazon-image.nix" ];

  documentation = {
    man.enable = false;
    nixos.enable = false;
    info.enable = false;
    doc.enable = false;
  };

  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" "en_US/ISO-8859-1" ];

  programs.sysdig.enable = true;

  environment = {
    systemPackages = with pkgs; [
      awscli
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

    variables = { AWS_DEFAULT_REGION = config.cluster.region; };
  };

  services = {
    ssm-agent.enable = lib.mkDefault true;
    openntpd.enable = lib.mkDefault true;
    consul.enable = lib.mkDefault true;
  };

  # Don't `nixos-rebuild switch` after the initial deploy.
  systemd.services.amazon-init.enable = lib.mkDefault false;

  boot.cleanTmpDir = true;

  time.timeZone = "UTC";

  networking = {
    hostName = nodeName;
    timeServers = lib.mkForce [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
      "2.nixos.pool.ntp.org"
      "3.nixos.pool.ntp.org"
    ];

    firewall = {
      # TODO: enable again
      enable = lib.mkDefault false;
      allowPing = lib.mkDefault true;
    };

    # each host gets mapped in the /etc/hosts
    # we also map vault.service.consul here for bootstrapping purposes
    extraHosts = let
      instances =
        lib.mapAttrsToList (name: instance: "${instance.privateIP} ${name}")
        config.cluster.instances;
    in lib.concatStringsSep "\n" (instances ++ [
      "${config.cluster.instances.core0.privateIP} vault.service.consul"
      "${config.cluster.instances.core1.privateIP} vault.service.consul"
      "${config.cluster.instances.core2.privateIP} vault.service.consul"
    ]);
  };

  age.secrets = {
    vault-full = {
      file = config.age.encryptedRoot + "/ssl/server-full.age";
      path = "/var/lib/vault/full.pem";
    };

    vault-ca = {
      file = config.age.encryptedRoot + "/ssl/ca.age";
      path = "/var/lib/vault/ca.pem";
    };

    vault-server = {
      file = config.age.encryptedRoot + "/ssl/server.age";
      path = "/var/lib/vault/server.pem";
    };

    vault-server-key = {
      file = config.age.encryptedRoot + "/ssl/server-key.age";
      path = "/var/lib/vault/server-key.pem";
    };

    vault-client = {
      file = config.age.encryptedRoot + "/ssl/client.age";
      path = "/var/lib/vault/client.pem";
    };

    vault-client-key = {
      file = config.age.encryptedRoot + "/ssl/client-key.age";
      path = "/var/lib/vault/client-key.pem";
    };
  };
}
