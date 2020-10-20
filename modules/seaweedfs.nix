{ config, pkgs, lib, nodeName, ... }:
let cfg = config.services.seaweedfs.master;
in {
  options = {
    services.seaweedfs.master = {
      enable = lib.mkEnableOption "Enable SeaweedFS master";

      port = lib.mkOption {
        type = lib.types.port;
        default = 9333;
      };

      peers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.forEach [ "core-1" "core-2" "core-3" ] (core:
          "${config.cluster.instances.${core}.privateIP}:${toString cfg.port}");
      };

      ip = lib.mkOption {
        type = lib.types.str;
        default = config.cluster.instances.${nodeName}.privateIP;
      };
    };
  };

  config = {
    systemd.services.seaweedfs-master =
      lib.mkIf config.services.seaweedfs.master.enable {
        description = "SeaweedFS master";
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "15s";
          StateDirectory = "seaweedfs-master";
          DynamicUser = true;
          User = "seaweedfs";
          Group = "seaweedfs";
          ExecStart =
            "@${pkgs.seaweedfs}/bin/weed weed master -mdir /var/lib/seaweedfs-master -peers ${
              lib.concatStringsSep "," cfg.peers
            } -ip ${cfg.ip} -port ${toString cfg.port}";
        };
      };
  };
}
