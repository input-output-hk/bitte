{ config, lib, pkgs, ... }:
let
  srvName = "spire-server";
  cfg = config.services.spire-server;
  settingsFormat = pkgs.formats.json {};
  renderedConfigFile = settingsFormat.generate "config.json" cfg.settings;
in {
  options.services.spire-server = {
    enable = lib.mkEnableOption "Enable the spire server.";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.spire-server;
    };

    configFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to hcl/json a configuration file.";
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeFormType = settingsFormat.type;

        # General options that are likely to be cross-referenced, so we type them:

        options.data_dir = lib.mkOption {
          type = lib.types.path;
          default = /var/lib/${srvName};
          description = "A directory the server can use for its runtime.";
        };

        options.bind_address = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "IP address or DNS name of the SPIRE server.";
        };

        options.bind_port = lib.mkOption {
          type = lib.types.port;
          default = 8081;
          description = "HTTP Port number of the SPIRE server.";
        };

        options.socket_path = lib.mkOption {
          type = lib.types.path;
          default = /run/${srvName}/private/api.sock;
          description = "Path to bind the SPIRE Server API socket to.";
        };

        options.log_file = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "File to write logs to.";
        };

        options.log_level = lib.mkOption {
          type = lib.types.enum [ "DEBUG" "INFO" "WARN" "ERROR" ];
          default = "INFO";
          description = "Sets the logging level.";
        };

        options.log_format = lib.mkOption {
          type = lib.types.enum [ "text" "json" ];
          default = "text";
          description = "Format of logs.";
        };
      };

      description = ''
        Configuration for the spire server. see <link xlink:href="https://github.com/spiffe/spire/blob/main/conf/server/server_full.conf"/>
        for supported values. Ignored if configFile is set.
      '';
    };

  };

  config = lib.mkIf cfg.enable {
    # Prefer the config file over rendered settings if both are set.
    services.spire-server.configFile = lib.mkDefault renderedConfigFile;

    # Sensible defaults
    services.spire-server.settings.NodeAttestor.join_token.plugin_data = {};
    services.spire-server.settings.KeyManager.memory.plugin_data = {};
    # TODO: telemetry & health-checks

    systemd.services.${srvName} = {
      description = "Spire Server daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        NoNewPrivileges = true;
        DynamicUser = true;
        RuntimeDirectory = lib.removePrefix "/run/" (builtins.dirOf cfg.socket_path);
        StateDirectory = lib.removePrefix "/var/lib/" cfg.data_dir;
        ExecStart = "${lib.getBin cfg.package}/bin/spire-server -c=${cfg.configFile}";
        Restart = "on-failure";
        ExecReload = "kill -HUP $MAINPID";
      };
    };

  };

}
