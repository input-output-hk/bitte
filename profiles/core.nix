{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [
    ./common.nix
    ./consul/server.nix
    ./nomad/server.nix
    ./telegraf.nix
    ./vault/server.nix
    ./secrets.nix
  ];

  services = {
    vault-agent-core.enable = true;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-server";
    vault-consul-token.enable = true;
    consul.enableDebug = false;
    seaweedfs = {
      master = {
        enable = true;
        peers = lib.forEach [ "core-1" "core-2" "core-3" ] (core:
          "${config.cluster.instances.${core}.privateIP}:${
            toString config.services.seaweedfs.master.port
          }");
        ip = config.cluster.instances.${nodeName}.privateIP;
        volumeSizeLimitMB = 10000;
      };
      volume = {
        enable = true;
        max = [ "1" ];
        dataCenter = config.cluster.region;
      };
    };
  };

  environment.systemPackages = with pkgs; [ sops awscli cachix cfssl tcpdump ];
}
