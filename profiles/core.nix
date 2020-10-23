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
    seaweedfs = let others = lib.remove nodeName [ "core-1" "core-2" "core-3" ]; in {
      master = {
        enable = true;
        peers = lib.forEach others (core:
          "${config.cluster.instances.${core}.privateIP}:${
            toString config.services.seaweedfs.master.port
          }");
        ip = config.cluster.instances.${nodeName}.privateIP;
        volumeSizeLimitMB = 1000;
      };

      volume = {
        enable = true;
        max = [ "0" ];
        dataCenter = config.cluster.region;
        mserver = lib.forEach others (core:
          "${config.cluster.instances.${core}.privateIP}:${
            toString config.services.seaweedfs.master.port
          }");
      };

      filer = {
        enable = true;

        master = lib.forEach others (core:
          "${config.cluster.instances.${core}.privateIP}:${
            toString config.services.seaweedfs.master.port
          }");

        peers = lib.forEach (lib.remove nodeName [ "core-3" ]) (core:
          "${config.cluster.instances.${core}.privateIP}:${
            toString config.services.seaweedfs.filer.http.port
          }");

        postgres.enable = true;
        postgres.hostname = "${nodeName}.node.consul";
        postgres.port = 26257;
      };
    };
  };

  environment.systemPackages = with pkgs; [ sops awscli cachix cfssl tcpdump ];
}
