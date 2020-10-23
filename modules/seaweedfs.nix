{ config, pkgs, lib, nodeName, ... }:
let
  masterCfg = config.services.seaweedfs.master;
  volumeCfg = config.services.seaweedfs.volume;
  filerCfg = config.services.seaweedfs.filer;
  mountCfg = config.services.seaweedfs.mount;
  node = config.cluster.instances.${nodeName} or null;

  join = builtins.concatStringsSep ",";

  toGoFlags = lib.flip lib.pipe [
    (builtins.map (e:
      let
        k = builtins.elemAt e 0;
        v = builtins.elemAt e 1;
        t = builtins.typeOf v;
      in if t == "bool" then
        lib.optional v k
      else if t == "list" then
        if builtins.length v > 0 then
          lib.optionals (v != [ ]) [ k (join v) ]
        else
          [ ]
      else
        lib.optionals (v != null) e))
    builtins.concatLists
    (builtins.map toString)
    (builtins.concatStringsSep " ")
  ];
in {
  options.services.seaweedfs.master = {
    enable = lib.mkEnableOption "Enable SeaweedFS master";
    peers = lib.mkOption { type = lib.types.listOf lib.types.str; };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9333;
    };
    ip = lib.mkOption { type = lib.types.str; };
    volumeSizeLimitMB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30000;
    };
  };

  options.services.seaweedfs.mount = {
    enable = lib.mkEnableOption "Enable SeaweedFS mount";

    mounts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "map of source to target mounts";
    };
  };

  options.services.seaweedfs.filer = {
    enable = lib.mkEnableOption "Enable SeaweedFS filer";

    collection = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "all data will be stored in this collection";
    };

    dataCenter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "prefer to write to volumes in this data center";
    };

    defaultReplicaPlacement = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description =
        "default replication type. If not specified, use master setting.";
    };

    dirListLimit = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "limit sub dir listing size (default 100000)";
    };

    disableDirListing = lib.mkEnableOption "turn off directory listing";

    disableHttp = lib.mkEnableOption
      "disable http request, only gRpc operations are allowed";

    encryptVolumeData = lib.mkEnableOption "encrypt data on volume servers";

    ip = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description =
        ''filer server http listen ip address (default "172.16.0.20")'';
    };

    ipBind = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if node == null then "0.0.0.0" else node.privateIP;
      description = ''ip address to bind to (default "0.0.0.0")'';
    };

    master = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = null;
      description =
        ''comma-separated master servers (default "localhost:9333")'';
    };

    maxMB = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "split files larger than the limit (default 32)";
    };

    metricsPort = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Prometheus metrics listen port";
    };

    peers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description =
        "all filers sharing the same filer store in an ip:port list";
    };

    http.port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "filer server http listen port (default 8888)";
    };

    http.readonly.port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "readonly http port opened to public";
    };

    s3.enable = lib.mkEnableOption "whether to start S3 gateway";

    s3.cert.file = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "path to the TLS certificate file";
    };

    s3.config = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "path to the config file";
    };

    s3.domainName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "suffix of the host name, {bucket}.{domainName}";
    };

    s3.key.file = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "path to the TLS private key file";
    };

    s3.port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = 8333;
      description = "s3 server http listen port (default 8333)";
    };

    postgres.enable = lib.mkEnableOption "run cockroachdb as well";

    postgres.hostname = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
    };

    postgres.port = lib.mkOption {
      type = lib.types.port;
      default = 5432;
    };
  };

  options.services.seaweedfs.volume = {
    enable = lib.mkEnableOption "Enable SeaweedFS volume";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "http listen port";
    };

    mserver = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = masterCfg.peers;
      description = "master servers";
    };

    minFreeSpacePercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 1;
      description =
        "minimum free disk space (default to 1%). Low disk space will mark all volumes as ReadOnly.";
    };

    dir = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/var/lib/seaweedfs-volume" ];
    };

    dataCenter = lib.mkOption { type = lib.types.str; };

    metricsPort = lib.mkOption {
      type = lib.types.port;
      default = 9334;
      description = "Prometheus metrics listen port";
    };

    max = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "8" ];
    };
  };

  config = {
    systemd.services.seaweedfs-volume = lib.mkIf volumeCfg.enable {
      description = "SeaweedFS volume";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "15s";
        StateDirectory = "seaweedfs-volume";
        DynamicUser = true;
        User = "seaweedfs";
        Group = "seaweedfs";
      };

      path = [ pkgs.gawk pkgs.iproute pkgs.seaweedfs ];
      script = let
        core-1 = config.cluster.instances.core-1.privateIP;
        ip = if node == null then
          ''"$(ip route get ${core-1} | awk '{ print $7 }')"''
        else
          node.privateIP;
        flags = toGoFlags [
          [ "-dir" (join volumeCfg.dir) ]
          [ "-metricsPort" volumeCfg.metricsPort ]
          [ "-minFreeSpacePercent" volumeCfg.minFreeSpacePercent ]
          [ "-dataCenter" volumeCfg.dataCenter ]
          [ "-max" volumeCfg.max ]
          [ "-mserver" volumeCfg.mserver ]
          [ "-ip" ip ]
          [ "-ip.bind" ip ]
          [ "-port" volumeCfg.port ]
        ];
      in ''
        exec weed -v 4 volume ${flags}
      '';
    };

    environment.etc."seaweedfs/filer.toml" = lib.mkIf filerCfg.enable {
      text = ''
        [filer.options]

        # with http DELETE, by default the filer would check whether a folder is empty.
        # recursive_delete will delete all sub folders and files, similar to "rm -Rf"
        recursive_delete = false

        # directories under this folder will be automatically creating a separate bucket
        buckets_folder = "/buckets"

        # a list of buckets with all write requests fsync=true
        buckets_fsync = [
          "nomad",
        ]

        [leveldb2]
        # local on disk, mostly for simple single-machine setup, fairly scalable
        # faster than previous leveldb, recommended.
        enabled = false
        dir = "."

        [postgres] # or cockroachdb
        enabled = true
        hostname = "${filerCfg.postgres.hostname}"
        port = ${toString filerCfg.postgres.port}
        database = "defaultdb"
        sslmode = "disable"
        username = "root"
        password = ""
        connection_max_idle = 100
        connection_max_open = 100
      '';
    };

    services.cockroachdb =
      lib.mkIf (filerCfg.enable && filerCfg.postgres.enable) {
        enable = true;
        insecure = true;
        listen.address = if node == null then "0.0.0.0" else node.privateIP;
        http.port = 58080;
        join = let others = lib.remove nodeName [ "core-1" "core-2" "core-3" ];
        in lib.concatStringsSep "," (lib.forEach others (core:
          "${config.cluster.instances.${core}.privateIP}:${
            toString config.services.cockroachdb.listen.port
          }"));
      };

    systemd.services.seaweedfs-filer = lib.mkIf filerCfg.enable {
      description = "SeaweedFS filer";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      restartTriggers =
        [ config.environment.etc."seaweedfs/filer.toml".source ];

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "15s";
        StateDirectory = "seaweedfs-filer";
        WorkingDirectory = "/var/lib/seaweedfs-filer";
        DynamicUser = true;
        User = "seaweedfs";
        Group = "seaweedfs";

        ExecStartPre = let
          init = pkgs.writeText "init.sql" ''
            CREATE TABLE IF NOT EXISTS filemeta (
              dirhash     BIGINT,
              name        VARCHAR(65535),
              directory   VARCHAR(65535),
              meta        bytea,
              PRIMARY KEY (dirhash, name)
            );
          '';
        in pkgs.writeShellScript "initdb" ''
          ${pkgs.cockroachdb}/bin/cockroach sql --insecure --host ${config.cluster.instances.core-1.privateIP}:26257 < ${init}
        '';
      };

      path = [ pkgs.gawk pkgs.iproute pkgs.seaweedfs ];

      script = let
        core-1 = config.cluster.instances.core-1.privateIP;
        ip = if node == null then
          ''"$(ip route get ${core-1} | awk '{ print $7 }')"''
        else
          node.privateIP;
        flags = toGoFlags [
          [ "-collection" filerCfg.collection ]
          [ "-dataCenter" filerCfg.dataCenter ]
          [ "-defaultReplicaPlacement" filerCfg.defaultReplicaPlacement ]
          [ "-dirListLimit" filerCfg.dirListLimit ]
          [ "-disableDirListing" filerCfg.disableDirListing ]
          [ "-disableHttp" filerCfg.disableHttp ]
          [ "-encryptVolumeData" filerCfg.encryptVolumeData ]
          [ "-ip" ip ]
          [ "-ip.bind" ip ]
          [ "-master" filerCfg.master ]
          [ "-maxMB" filerCfg.maxMB ]
          [ "-metricsPort" filerCfg.metricsPort ]
          [ "-peers" filerCfg.peers ]
          [ "-port" filerCfg.http.port ]
          [ "-port.readonly" filerCfg.http.readonly.port ]
          [ "-s3" filerCfg.s3.enable ]
          [ "-s3.cert.file" filerCfg.s3.cert.file ]
          [ "-s3.config" filerCfg.s3.config ]
          [ "-s3.domainName" filerCfg.s3.domainName ]
          [ "-s3.key.file" filerCfg.s3.key.file ]
          [ "-s3.port" filerCfg.s3.port ]
        ];
      in ''
        exec weed -v 4 filer ${flags}
      '';
    };

    systemd.services.seaweedfs-master = lib.mkIf masterCfg.enable {
      description = "SeaweedFS master";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "15s";
        StateDirectory = "seaweedfs-master";
        DynamicUser = true;
        User = "seaweedfs";
        Group = "seaweedfs";
        ExecStart = let
          flags = toGoFlags [
            [ "-mdir" "/var/lib/seaweedfs-master" ]
            [ "-peers" masterCfg.peers ]
            [ "-ip" masterCfg.ip ]
            [ "-ip.bind" masterCfg.ip ]
            [ "-port" masterCfg.port ]
            [ "-volumeSizeLimitMB" masterCfg.volumeSizeLimitMB ]
            [ "-volumePreallocate" true ]
          ];
        in "@${pkgs.seaweedfs}/bin/weed weed -v 3 master ${flags}";
      };
    };

    # seaweedfs-mount@source:target
    # will mount the seaweedfs path `/source` to `/var/lib/seaweedfs-mount/target`

    systemd.services."seaweedfs-mount@" = lib.mkIf mountCfg.enable {
      description = "SeaweedFS mount %I";
      scriptArgs = "%i";

      path = with pkgs; [ gawk iproute seaweedfs utillinux ];

      script = let
        core-1 = config.cluster.instances.core-1.privateIP;
        ip = if node == null then
          ''"$(ip route get ${core-1} | awk '{ print $7 }')"''
        else
          node.privateIP;
      in ''

        IFS=':' read -a args <<< "$1"

        export PATH="${config.security.wrapperDir}:$PATH"

        source="/buckets/''${args[0]}"
        target="/var/lib/seaweedfs-mount/''${args[1]}"

        if mount | grep "$target"; then
          umount -f "$target" || umount -l "$target"
        fi

        mkdir -p "$target"
        chmod 0777 "$target"

        exec weed -v 4 mount \
          -dirAutoCreate \
          -filer ${config.cluster.instances.core-3.privateIP}:8888 \
          -filer.path "$source" \
          -dir "$target"
      '';
    };

    systemd.targets.seaweedfs-mount = lib.mkIf mountCfg.enable {
      description = "Target to start all default seaweedfs-mount@ services";
      unitConfig.X-StopOnReconfiguration = true;
      wants = lib.mapAttrsToList
        (name: value: "seaweedfs-mount@${name}:${value}.service")
        mountCfg.mounts;
      wantedBy = [ "multi-user.target" ];
    };
  };
}
