{ config, self, pkgs, lib, nodeName, ... }:
let
  cfg = config.services.glusterfs;
in {
  services.glusterfs.enable = true;

  systemd.services.glusterd = lib.mkIf cfg.enable {
    path = with pkgs; [ nettools ];
  };

  fileSystems."/mnt/gv0" = lib.mkIf cfg.enable {
    device = "glusterd.service.consul:/gv0";
    fsType = "glusterfs";
  };

  systemd.services."mnt-gv0.mount" = lib.mkIf cfg.enable {
    after = [ "consul.service" ];
    wants = [ "consul.service" ];
  };

  systemd.services.nomad = lib.mkIf cfg.enable {
    after = [ "mnt-gv0.mount" ];
  };
}
