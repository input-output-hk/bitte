{ self, pkgs, config, lib, ... }: {
  imports = [
    ./common.nix
    ./consul/client.nix
    ./docker.nix
    ./nomad/client.nix
    ./telegraf.nix
    ./vault/client.nix
    ./secrets.nix
  ];

  services = {
    amazon-ssm-agent.enable = true;
    vault-agent-client.enable = true;
    nomad.enable = true;
    telegraf.extraConfig.global_tags.role = "consul-client";
    seaweedfs.volume = {
      enable = true;
      max = [ "0" ];
      dataCenter = config.asg.region;
      mserver = lib.forEach [ "core-1" "core-2" "core-3" ] (core:
        "${config.cluster.instances.${core}.privateIP}:${
          toString config.services.seaweedfs.master.port
        }");
    };
  };

  boot.cleanTmpDir = true;

  time.timeZone = "UTC";
  networking.firewall.enable = false;
}
