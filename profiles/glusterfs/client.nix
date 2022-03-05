{ config, self, pkgs, nodeName, ... }: {
  services.glusterfs.enable = true;
  systemd.services.glusterd.path = with pkgs; [ nettools ];

  fileSystems."/mnt/gv0" = {
    device = "glusterd.service.consul:/gv0";
    fsType = "glusterfs";
  };

  systemd.services."mnt-gv0.mount" = {
    after = [ "consul.service" ];
    wants = [ "consul.service" ];
  };

}
