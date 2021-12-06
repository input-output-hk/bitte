{ config, pkgs, lib, pkiFiles, ... }:

{
  options = {
    services.ingress = { enable = lib.mkEnableOption "Enable Ingress"; };
  };
  config = {

    systemd.services.ingress = lib.mkIf config.services.ingress.enable {
      description = "HAProxy (ingress)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      unitConfig = {
        StartLimitInterval = "20s";
        StartLimitBurst = 10;
      };

      serviceConfig = let
        preScript = pkgs.writeShellScript "ingress-start-pre" ''
          export PATH="${lib.makeBinPath [ pkgs.coreutils ]}"
          set -exuo pipefail
          cp ${pkiFiles.keyFile} consul-key.pem
          cp ${pkiFiles.caCertFile} consul-ca.pem
          cat ${pkiFiles.certChainFile} ${pkiFiles.keyFile} > consul-crt.pem

          cat /etc/ssl/certs/${config.cluster.domain}-{cert,key}.pem \
            ${../lib/letsencrypt.pem} \
          > acme-full.pem

          # when the master process receives USR2, it reloads itself using exec(argv[0]),
          # so we create a symlink there and update it before reloading
          ln -sf ${pkgs.haproxy}/sbin/haproxy /run/ingress/haproxy
          # when running the config test, don't be quiet so we can see what goes wrong
          /run/ingress/haproxy -c -f /var/lib/ingress/haproxy.conf

          chown --reference . --recursive .
        '';
      in {
        StateDirectory = "ingress";
        RuntimeDirectory = "ingress";
        WorkingDirectory = "/var/lib/ingress";
        DynamicUser = true;
        User = "ingress";
        Group = "ingress";
        Type = "notify";
        ExecStartPre = "!${preScript}";
        ExecStart =
          "/run/ingress/haproxy -Ws -f /var/lib/ingress/haproxy.conf -p /run/ingress/haproxy.pid";
        # support reloading
        ExecReload = [
          "${pkgs.haproxy}/sbin/haproxy -c -f /var/lib/ingress/haproxy.conf"
          "${pkgs.coreutils}/bin/ln -sf ${pkgs.haproxy}/sbin/haproxy /run/ingress/haproxy"
          "${pkgs.coreutils}/bin/kill -USR2 $MAINPID"
        ];
        KillMode = "mixed";
        SuccessExitStatus = "143";
        Restart = "always";
        TimeoutStopSec = "30s";
        RestartSec = "5s";
        # upstream hardening options
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallFilter =
          "~@cpu-emulation @keyring @module @obsolete @raw-io @reboot @swap @sync";
        # needed in case we bind to port < 1024
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      };
    };
  };

}
