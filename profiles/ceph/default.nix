{ pkgs, config, ... }: {
  imports = [ ../common.nix ../telegraf.nix ];

  environment.systemPackages = with pkgs; [ ceph xfsprogs netcat-openbsd ];

  boot.kernelModules = [ "xfs" ];

  services = {
    ceph = {
      enable = true;

      global = {
        fsid = "7603b881-c1f8-487c-995e-50ac5d2ee0ee";
        monHost = config.cluster.instances.mon-0.privateIP;
        monInitialMembers = "mon-0";
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
