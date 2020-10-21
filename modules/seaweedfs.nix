{ config, pkgs, lib, nodeName, ... }:
let
  masterCfg = config.services.seaweedfs.master;
  volumeCfg = config.services.seaweedfs.volume;
  filerCfg = config.services.seaweedfs.filer;

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
        lib.optionals (v != [ ]) [k (join v) ]
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
      default = null;
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
      type = lib.types.nullOr lib.types.str;
      default = null;
      description =
        "all filers sharing the same filer store in comma separated ip:port list";
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
  };

  options.services.seaweedfs.volume = {
    enable = lib.mkEnableOption "Enable SeaweedFS volume";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "http listen port";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      default = config.cluster.instances.${nodeName}.privateIP or "127.0.0.1";
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
        ExecStart = builtins.concatStringsSep " " [
          "@${pkgs.seaweedfs}/bin/weed"
          "weed"
          "volume"
          "-dir"
          (join volumeCfg.dir)
          "-metricsPort"
          (toString volumeCfg.metricsPort)
          "-minFreeSpacePercent"
          (toString volumeCfg.minFreeSpacePercent)
          "-dataCenter"
          volumeCfg.dataCenter
          "-max"
          (join volumeCfg.max)
          "-mserver"
          (join volumeCfg.mserver)
          "-ip"
          volumeCfg.ip
          "-port"
          (toString volumeCfg.port)
        ];
      };
    };

    environment.etc."seaweedfs/filer.toml" = lib.mkIf filerCfg.enable {
      text = ''
        [filer.options]
        # with http DELETE, by default the filer would check whether a folder is empty.
        # recursive_delete will delete all sub folders and files, similar to "rm -Rf"
        recursive_delete = false
        # directories under this folder will be automatically creating a separate bucket
        buckets_folder = "/buckets"
        buckets_fsync = [          # a list of buckets with all write requests fsync=true
          "important_bucket",
          "should_always_fsync",
        ]

        [leveldb2]
        # local on disk, mostly for simple single-machine setup, fairly scalable
        # faster than previous leveldb, recommended.
        enabled = true
        dir = "."
      '';
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
        ExecStart = let
          flags = toGoFlags [
            [ "-collection" filerCfg.collection ]
            [ "-dataCenter" filerCfg.dataCenter ]
            [ "-defaultReplicaPlacement" filerCfg.defaultReplicaPlacement ]
            [ "-dirListLimit" filerCfg.dirListLimit ]
            [ "-disableDirListing" filerCfg.disableDirListing ]
            [ "-disableHttp" filerCfg.disableHttp ]
            [ "-encryptVolumeData" filerCfg.encryptVolumeData ]
            [ "-ip" filerCfg.ip ]
            [ "-ip.bind" filerCfg.ipBind ]
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
          # "core-1.node.consul:9333,core-2.node.consul:9333,core-3.node.consul:9333"
        in "@${pkgs.seaweedfs}/bin/weed weed filer ${flags}";
      };
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
        ExecStart =
          "@${pkgs.seaweedfs}/bin/weed weed master -mdir /var/lib/seaweedfs-master -peers ${
            join masterCfg.peers
          } -ip ${masterCfg.ip} -port ${
            toString masterCfg.port
          } -volumeSizeLimitMB ${toString masterCfg.volumeSizeLimitMB}";
      };
    };
  };
}
