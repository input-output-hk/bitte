{ nodeName, pkgs, lib, config, ... }:
let keyFile = "osd-${nodeName}.json";
in {
  imports = [ ./default.nix ];

  services = {
    telegraf.extraConfig.global_tags.role = "ceph-osd";

    ceph = {
      osd = {
        enable = true;
        daemons = [ nodeName ];
      };
    };
  };

  secrets.generate.osd = ''
    export PATH="${lib.makeBinPath (with pkgs; [ coreutils sops toybox ceph jq ])}"
    target="encrypted/${keyFile}"

    if [ ! -s "$target" ]; then
      uuid="$(uuidgen)"
      key="$(ceph-authtool --gen-print-key)"

      echo '{}' \
      | jq --arg uuid "$uuid" '.uuid = $uuid' \
      | jq --arg key "$key" '.cephx_secret = $key' \
      | sops --encrypt kms '${config.cluster.kms}' /dev/stdin \
      > "$target.tmp"
      mv "$target.tmp" "$target"
    fi
  '';

  secrets.install.osd = {
    source = config.secrets.encryptedRoot + "/${keyFile}";
    target = /run/keys/osd.json;
  };

  systemd.services.ceph-osd-setup = {
    wantedBy = [ "multi-user.target" ];
    before = [ "ceph-osd-${nodeName}" ];
    path = with pkgs; [ systemd ceph gnugrep vault jq ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "20s";
      ExecStart = pkgs.writeBashChecked "ceph-osd-setup.sh" ''
        set -exuo pipefail

        key="$(jq -e -r .cephx_secret < /run/keys/osd.json)"
        uuid="$(jq -e -r .uuid < /run/keys/osd.json)"

        mkfs.xfs /dev/vdb
        mkdir -p "/var/lib/ceph/osd/ceph-${nodeName}"

        mount /dev/vdb "/var/lib/ceph/osd/ceph-${nodeName}"

        ceph-authtool \
          --create-keyring "/var/lib/ceph/osd/ceph-${nodeName}/keyring" \
          --name "osd.${nodeName}" \
          --add-key "$key"

        jq -e '{cephx_secret: .cephx_secret}' \
        < /run/keys/osd.json \
        | ceph osd new "$uuid" -i -

        ceph-osd -i "${nodeName}" --mkfs --osd-uuid "$uuid"
        chown -R ceph:ceph /var/lib/ceph/osd
        systemctl start ceph-osd-${nodeName}
      '';
    };
  };
}
