{ pkgs, lib, config, ... }:
let
  keyFile = "mon.json";
  cfg = config.services.ceph;

  sopsDecrypt = path:
    "${pkgs.sops}/bin/sops --decrypt --input-type json ${path}";
in {
  imports = [ ./default.nix ];

  services = {
    telegraf.extraConfig.global_tags.role = "ceph-mon";

    ceph = {
      mon = {
        enable = true;
        daemons = [ "monA" ];
      };

      mgr = {
        enable = true;
        daemons = [ "monA" ];
      };
    };

    networking = {
      firewall = {
        allowedTCPPorts = [ 6789 3300 ];
        allowedTCPPortRanges = [{
          from = 6800;
          to = 7300;
        }];
      };
    };
  };

  systemd.services.ceph-mon-setup = let name = "mon-0";
  in {
    wantedBy = [ "multi-user.target" ];
    before = [ "ceph-mon-${name}" ];
    path = with pkgs; [ systemd ceph gnugrep vault ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "20s";
      ExecStart = pkgs.writeBashChecked "ceph-mon-setup.sh" ''
        set -exuo pipefail

        if [ -s /var/lib/ceph/mgr/ceph-${name}/keyring ]; then
          exit 0
        fi

        vault kv put kv/bootstrap/ceph/keyring - \
        < /run/keys/ceph.client.admin.keyring

        monmaptool \
          --create \
          --add ${name} ${config.cluster.instances.${name}.privateIP} \
          --fsid ${cfg.global.fsid} \
          /tmp/monmap

        ceph ceph-mon --mkfs \
          -i ${cfg.monA.name} \
          --monmap /tmp/monmap \
          --keyring /run/keys/ceph.mon.keyring

        ceph mkdir -p /var/lib/ceph/mgr/ceph-${name}/
        ceph touch /var/lib/ceph/mon/ceph-${name}/done

        systemctl start ceph-mon-${name}
        ceph mon enable-msgr2

        ceph -s | grep 'mon: 1 daemons'

        ceph auth get-or-create mgr.${name} mon 'allow profile mgr' osd 'allow *' mds 'allow *' \
        > /var/lib/ceph/mgr/ceph-${name}/keyring
        systemctl start ceph-mgr-${name}
      '';
    };
  };

  secrets.generate.mon = ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils sops toybox ceph ])}"
    target="encrypted/${keyFile}"

    if [ ! -s "$target" ]; then
      rm -f secrets/ceph*

      # Create a keyring for your cluster and generate a monitor secret key.

      ceph-authtool --create-keyring secrets/ceph.mon.keyring \
        --gen-key -n mon. \
        --cap mon 'allow *'

      # Generate an administrator keyring, generate a client.admin user and add
      # the user to the keyring.

      ceph-authtool --create-keyring secrets/ceph.client.admin.keyring \
        --gen-key -n client.admin \
        --cap mon 'allow *' \
        --cap osd 'allow *' \
        --cap mds 'allow *' \
        --cap mgr 'allow *'

      # Generate a bootstrap-osd keyring, generate a client.bootstrap-osd user
      # and add the user to the keyring.

      ceph-authtool --create-keyring secrets/ceph.keyring \
        --gen-key -n client.bootstrap-osd \
        --cap mon 'profile bootstrap-osd' \
        --cap mgr 'allow r'

      ceph-authtool secrets/ceph.mon.keyring --import-keyring secrets/ceph.client.admin.keyring
      ceph-authtool secrets/ceph.mon.keyring --import-keyring secrets/ceph.keyring

      echo '{}' \
      | jq --arg val "$(< secrets/ceph.mon.keyring)"          '.mon_keyring = $val' \
      | jq --arg val "$(< secrets/ceph.client.admin.keyring)" '.client_admin_keyring = $val' \
      | jq --arg val "$(< secrets/ceph.keyring)"              '.keyring = $val' \
      | sops --encrypt kms '${config.cluster.kms}' /dev/stdin \
      > "$target.tmp"
      mv "$target.tmp" "$target"
    fi
  '';

  secrets.install.mon = {
    script = ''
      export PATH="${lib.makeBinPath (with pkgs; [ jq coreutils ])}"
      secret="$(${sopsDecrypt (config.secrets.encryptedRoot + "/${keyFile}")})"
      echo "$secret" | jq -r -e .mon_keyring          > /run/keys/ceph.mon.keyring
      echo "$secret" | jq -r -e .client_admin_keyring > /run/keys/ceph.client.admin.keyring
      echo "$secret" | jq -r -e .keyring              > /run/keys/ceph.keyring
    '';
  };
}
