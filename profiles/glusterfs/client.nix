{
  config,
  self,
  pkgs,
  lib,
  nodeName,
  ...
}: let
  cfg = config.services.glusterfs;
in {
  services.glusterfs.enable = lib.mkDefault true;

  systemd.services.glusterd = lib.mkIf cfg.enable {
    path = with pkgs; [nettools];
  };

  systemd.mounts = [
    (lib.mkIf cfg.enable {
      after = ["consul.service" "dnsmasq.service"];
      wants = ["consul.service" "dnsmasq.service"];
      what = "glusterd.service.consul:/gv0";
      where = "/mnt/gv0";
      type = "glusterfs";
    })
  ];

  systemd.services.nomad = lib.mkIf cfg.enable {
    after = ["mnt-gv0.mount"];
  };
}
