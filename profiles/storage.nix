{ config, pkgs, lib, ... }:
{
  imports = [
    ./common.nix

    ./consul/client.nix
    ./vault/aux.nix

    ./glusterfs/storage.nix
  ];
  systemd.services."mnt-gv0.mount" = {
    after = [ "setup-glusterfs.service" ];
    wants = [ "setup-glusterfs.service" ];
  };

  systemd.services.storage-service = (pkgs.consulRegister {
    inherit pkiFiles;
    service = {
      name = "glusterd";
      port = 24007;
      tags = [ "gluster" "server" ];

      checks = {
        gluster-tcp = {
          interval = "10s";
          timeout = "5s";
          tcp = "localhost:24007";
        };

        # gluster-pool = {
        #   interval = "10s";
        #   timeout = "5s";
        #   args = let
        #     script = pkgs.writeBashChecked "gluster-pool-check.sh" ''
        #       set -exuo pipefail
        #       export PATH="${
        #         lib.makeBinPath (with pkgs; [ glusterfs gnugrep ])
        #       }"
        #       exec gluster pool list | egrep -v 'UUID|localhost' | grep Connected
        #     '';
        #   in [ script ];
        # };
      };
    };
  }).systemdService;
}
