{ pkgs, config, nodeName, ... }: {
  imports = [ ../common.nix ../telegraf.nix ];

  environment.systemPackages = with pkgs; [ ceph xfsprogs netcat-openbsd ];

  boot.kernelModules = [ "xfs" ];

  services = {
    ceph = {
      enable = true;

      extraConfig = {
        public_addr = config.cluster.instances.${nodeName}.privateIP;
      };

      global = {
        fsid = "7603b881-c1f8-487c-995e-50ac5d2ee0ee";
        monHost = config.cluster.instances.monitoring.privateIP;
        monInitialMembers = "monitoring";
      };

      rgw = {
        enable = true;
        daemons = [nodeName];
      };
    };
  };

  networking = {
    firewall = {
      allowedTCPPortRanges = [{
        from = 6800;
        to = 7300;
      }];
    };
  };
}
