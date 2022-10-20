{
  pkgs,
  lib,
  inputs,
  config,
  ...
}: let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool ints nullOr str;

  ziti-edge-tunnel = inputs.openziti.packages.x86_64-linux.ziti-edge-tunnel_latest;
  cfg = config.services.ziti-edge-tunnel;
in {
  options.services.ziti-edge-tunnel = {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable the OpenZiti edge tunnel service.
      '';
    };

    enableResolved = mkOption {
      type = bool;
      default = true;
      description = ''
        Enabled systemd resolved which ziti-edge-tunnel will use preferentially for a dns hook.
      '';
    };

    dnsRegexStopPost = mkOption {
      type = str;
      default = "^nameserver 100.64.0";
      description = ''
        The string used in gnused to clean /etc/resolv.conf when it is a regular file after stopping the ziti-edge-tunnel
        service to prevent a dead resolver from being left behind.
      '';
    };

    dnsIpRange = mkOption {
      type = str;
      default = "100.64.0.1/11";
      description = ''
        Specify CIDR block in which service DNS names are assigned in N.N.N.N/n format (default 100.64.0.1/11).

        Note:
          tunX device should appears at the declared IP in this CIDR block range (default: 100.64.0.1).
          ziti-edge-tunnel DNS binding will appear at the second assignable IP in the CIDR block range (default: 100.64.0.2)
      '';
    };

    dnsUpstream = mkOption {
      type = nullOr str;
      default = "8.8.8.8";
      description = ''
        Default upstream to resolve queries if the query is not a known ziti hostname.
        Set to null to disable upstream call behavior.
      '';
    };

    identityDir = mkOption {
      type = str;
      default = "/var/lib/ziti/identity";
      description = ''
        Load identities from provided directory.
      '';
    };

    refresh = mkOption {
      type = ints.positive;
      default = 10;
      description = ''
        Set service polling interval in seconds (default 10).
      '';
    };

    verbosity = mkOption {
      type = ints.positive;
      default = 3;
      description = ''
        Set log level, higher level -- more verbose (default 3)."
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      step-cli
      ziti-edge-tunnel
    ];

    services.resolved.enable = cfg.enableResolved;

    systemd.services.ziti-edge-tunnel = {
      wantedBy = ["multi-user.target"];

      startLimitIntervalSec = 0;
      startLimitBurst = 0;

      path = with pkgs; [bash coreutils fd gnugrep gnused iproute2 ziti-edge-tunnel];

      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
        StateDirectory = "ziti";
        WorkingDirectory = "/var/lib/ziti";
        LimitNOFILE = 65535;

        ExecStartPre = let
          preScript = pkgs.writeShellApplication {
            name = "ziti-edge-tunnel-startPre.sh";
            text = ''
              mkdir -p ${cfg.identityDir}

              echo "Processing $(fd -e jwt . identity | wc -l) JWT enrollment token(s)..."
              # shellcheck disable=SC1004
              fd -e jwt . identity/ -x \
                bash -c ' \
                  echo "Enrolling JWT {}" \
                    && ziti-edge-tunnel enroll --jwt {} --identity {.}.json \
                    && echo "Enrolled JWT {} as identity {.}.json" \
                    && echo "Cleaning up JWT {}" \
                    && rm -v {} \
                '
            '';
          };
        in "${preScript}/bin/ziti-edge-tunnel-startPre.sh";

        ExecStart = let
          script = pkgs.writeShellApplication {
            name = "ziti-edge-tunnel";
            text = ''
              exec ${ziti-edge-tunnel}/bin/ziti-edge-tunnel run \
                --identity-dir identity \
                --verbose ${toString cfg.verbosity} \
                --refresh ${toString cfg.refresh}  \
                ${if cfg.dnsUpstream == null then "\\\n" else "--dns-upstream ${cfg.dnsUpstream} \\"}
                --dns-ip-range ${cfg.dnsIpRange}
            '';
          };
        in "${script}/bin/ziti-edge-tunnel";

        ExecStopPost = let
          postScript = pkgs.writeShellApplication {
            name = "ziti-edge-tunnel-stopPost.sh";
            text = ''
              # Ensure ziti-edge-tunnel doesn't leave a dead resolver behind when /etc/resolv.conf is a regular file
              if [ ! -L /etc/resolv.conf ]; then
                echo "Purging ziti DNS resolver from /etc/resolv.conf upon service shutdown."
                sed -i '/${cfg.dnsRegexStopPost}/d' /etc/resolv.conf
              fi
            '';
          };
        in "${postScript}/bin/ziti-edge-tunnel-stopPost.sh";
      };
    };
  };
}
