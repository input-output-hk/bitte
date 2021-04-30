{ config, self, pkgs, nodeName, ... }: {
  imports = [
    (self.inputs.bitte + "/profiles/common.nix")
    (self.inputs.bitte + "/profiles/telegraf.nix")
    (self.inputs.bitte + "/profiles/secrets.nix")
    (self.inputs.bitte + "/profiles/vault/client.nix")
  ];

  services.glusterfs.enable = true;
  services.vault-agent-core = {
    enable = true;
    vaultAddress = "https://${config.cluster.instances.core-2.privateIP}:8200";
  };

  systemd.services.glusterd.path = with pkgs; [ nettools ];

  boot.kernelModules = [ "xfs" ];

  fileSystems = {
    "/data/brick1" = {
      label = "brick";
      device = "/dev/nvme1n1";
      fsType = "xfs";
      formatOptions = "-i size=512";
      autoFormat = true;
    };

    "/mnt/gv0" = {
      device = "${nodeName}:/gv0";
      fsType = "glusterfs";
    };
  };

  systemd.services."mnt-gv0.mount" = {
    after = [ "setup-glusterfs.service" ];
    wants = [ "setup-glusterfs.service" ];
  };

  systemd.services.setup-glusterfs = {
    wantedBy = [ "multi-user.target" ];
    after = [ "glusterfs.service" ];
    path = with pkgs; [ glusterfs gnugrep xfsprogs utillinux jq ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "20s";
      ExecStart = pkgs.writeBashChecked "setup-glusterfs.sh" ''
        set -exuo pipefail

        for peer in storage-{0..2}; do
          gluster peer probe $peer
        done

        xfs_growfs /data/brick1

        mkdir -p /data/brick1/gv0
        if ! gluster volume info 2>&1 | grep 'Volume Name: gv0'; then
          gluster volume create gv0 \
            disperse 3 \
            redundancy 1 \
            storage-0:/data/brick1/gv0 \
            storage-1:/data/brick1/gv0 \
            storage-2:/data/brick1/gv0 \
            force
        fi

        gluster volume start gv0 force

        size="$(lsblk /dev/nvme1n1 -J | jq -r -e '.blockdevices[0].size')B"
        gluster volume quota gv0 limit-usage / "$size"
      '';
    };
  };
}
