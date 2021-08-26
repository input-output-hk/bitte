{ self, config, pkgs, lib, ... }:

let cfg = config.services.vulnix;
in {
  options.services.vulnix = with lib; {
    enable = mkEnableOption "Vulnix scan";

    package = mkOption {
      type = types.package;
      default = pkgs.vulnix;
      defaultText = "pkgs.vulnix";
      description = "The Vulnix distribution to use.";
    };

    scanRequisites = mkEnableOption "scan of transitive closures" // {
      default = true;
    };

    scanSystem = mkEnableOption "scan of the current system" // {
      default = true;
    };

    scanGcRoots = mkEnableOption "scan of all active GC roots";

    paths = mkOption {
      type = with types; listOf str;
      default = [];
      description = "Paths to scan.";
    };

    extraOpts = mkOption {
      type = with types; listOf str;
      default = [];
      description = ''
        Extra options to pass to Vulnix. See the README:
        <link xlink:href="https://github.com/flyingcircusio/vulnix/blob/master/README.rst"/>
        or <command>vulnix --help</command> for more information.
      '';
    };

    systemdServiceName = mkOption {
      readOnly = true;
      type = types.str;
      default = "vulnix";
      description = ''
        The name of the systemd service unit without extension.
        Use this to process the vulnix output by further tweaking to the service unit.
        The report is written to <filename>$RUNTIME_DIRECTORY/report.json</filename>.
      '';
    };
  };

  config.systemd = lib.mkIf cfg.enable {
    services.${cfg.systemdServiceName} = {
      description = "Vulnix scan";
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        RuntimeDirectory = "vulnix";
        CacheDirectory = "vulnix";
      };
      script = ''
        vulnix ${lib.concatStringsSep " " (
          lib.cli.toGNUCommandLine {} (with cfg; {
            json = true;
            cache-dir = "$CACHE_DIRECTORY";
            requisites = scanRequisites;
            no-requisites = !scanRequisites;
            system = scanSystem;
            gc-roots = scanGcRoots;
          })
        )} \
          ${lib.concatStringsSep " " cfg.extraOpts} \
          -- ${lib.escapeShellArgs cfg.paths} \
          > $RUNTIME_DIRECTORY/report.json ||
        {
          code=$?
          if [[ $code != 2 ]]; then
            exit $code
          fi
        }
      '';
      path = [ cfg.package ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
