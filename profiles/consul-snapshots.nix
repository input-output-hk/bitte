{ config, pkgs, ... }:

{

  services.logrotate = {
    enable = true;
    paths = {
      consul-snapshots = {
        path = "/var/lib/private/consul/snapshots/*.snap";
        user = config.services.consul.user;
        group = config.services.consul.group;
        keep = 7;
      };
    };
  };

  systemd = {
    timers.consul-snapshots = {
      partOf = [ "consul-snapshots.service" ];
      timerConfig = {
        OnCalendar = "daily"; # Consul "Enterprise" defaults to hourly
      };
      wantedBy = [ "timers.target" ];
    };
    services.consul-snapshots = {
      serviceConfig.Type = "oneshot";
      script = ''
        #!/run/current-system/sw/bin/bash

        set -exuo pipefail

        SNAPSHOTDIR="/var/lib/private/consul/snapshots"
        CONSULACL="consul:consul"
        CONSULPERMISSIONS="700"

        checkSnapshotsDir () {
            if [ ! -d $SNAPSHOTDIR ]; then
                mkdir $SNAPSHOTDIR;
                chown $CONSULACL $SNAPSHOTDIR;
                chmod $CONSULPERMISSIONS $SNAPSHOTDIR;
            fi
        }

        # Is the host the consul leader?
        isNotLeader () {
            if [[ $(consul info | grep 'leader =' | awk '{print $3}') = false ]]; then
                return
            fi

            false
        }

        # Take the snapshot
        takeConsulSnapshot () {
            consul snapshot save $SNAPSHOTDIR/consul-"$(hostname)".snap
        }

        if isNotLeader; then
            checkSnapshotsDir
            takeConsulSnapshot
        fi
      '';
    };
  };

}
