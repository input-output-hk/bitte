{ lib, config, pkgs, ... }:
let cfg = config.services.nomad-autoscaler;
  inherit (lib) mkOption mkEnableOption types mkIf;
  inherit (types) enum path package;
  inherit (pkgs) sanitize;
in
{
  options.services.nomad-autoscaler = {
    enable = mkEnableOption "nomad-autoscaler";

    package = mkOption {
      type = package;
      default = pkgs.nomad-autoscaler;
      description = "The nomad-autoscaler package to use.";
    };

    logLevel = mkOption {
      type = enum [ "DEBUG" "INFO" "WARN" ];
      default = "INFO";
      description = ''
        Specify the verbosity level of Nomad Autoscaler's logs.
        Valid values include DEBUG, INFO, and WARN, in decreasing order of verbosity.
      '';
    };

    logJson = mkEnableOption "Output logs in a JSON format";

    pluginDir = mkOption {
      type = path;
      default = "${cfg.package.src}/plugins";
      description = ''
        The plugin directory is used to discover Nomad Autoscaler plugins.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.etc."nomad-autoscaler.d/config.json".source =
      pkgs.toPrettyJSON "config" (sanitize {
        inherit (cfg) pluginDir logJson logLevel;
      });

    systemd.services.nomad-autoscaler = {
      description = "Nomad Autoscaler Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        StateDirectory = "nomad-autoscaler";
        RuntimeDirectory = "nomad-autoscaler";
        DynamicUser = true;
        User = "nomad-autoscaler";
        Group = "nomad-autoscaler";
        ExecStart =
          "${cfg.package}/bin/nomad-autoscaler agent -config /etc/nomad-autoscaler.d/config.json";
        # support reloading
        ExecReload = [
        ];
        Restart = "on-failure";
        StartLimitInterval = "20s";
        StartLimitBurst = 10;
        TimeoutStopSec = "30s";
        RestartSec = "5s";
        # upstream hardening options
        NoNewPrivileges = true;
        ProtectHome = true;
        # ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallFilter =
          "~@cpu-emulation @keyring @module @obsolete @raw-io @reboot @swap @sync";
      };

    };
  };
}
