{ config, lib, pkgs, ... }:
let
  srvName = "spire-agent";
  cfg = config.services.${srvName};
  settingsFormat = pkgs.formats.json {};
  renderedConfigFile = settingsFormat.generate "config.json" cfg.settings;
in {
  options.services.spire-agent = {
    enable = lib.mkEnableOption "Enable the spire agent.";

    package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.spire-agent;
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
          description = "A directory the agent can use for its runtime.";
        };

        options.server_address = lib.mkOption {
          type = lib.types.str;
          description = "IP address or DNS name of the SPIRE server.";
        };

        options.server_port = lib.mkOption {
          type = lib.types.port;
          default = 8081;
          description = "HTTP Port number of the SPIRE server.";
        };

        options.socket_path = lib.mkOption {
          type = lib.types.path;
          default = /run/${srvName}/public/api.sock;
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
        Configuration for the spire agent. see <link xlink:href="https://github.com/spiffe/spire/blob/main/conf/agent/agent_full.conf"/>
        for supported values. Ignored if configFile is set.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Prefer the config file over rendered settings if both are set.
    services.spire-agent.configFile = mkDefault renderedConfigFile;

    # Sensible defaults
    services.spire-agent.settings.KeyManager.memory.plugin_data = {};
    services.spire-agent.settings.WorkloadAttestor.unix.plugin_data = {
      discover_workload_path = true; # use nix store paths as selectors
      workload_size_limit = -1; # never calculate the hash, nix store path are already hashed
    };
    # TODO: telemetry & health-checks

    systemd.services.${srvName} = {
      description = "Spire Agent daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        NoNewPrivileges = true;
        DynamicUser = true; # TODO: check unix workload attestor requirements w.r.t. root
        RuntimeDirectory = lib.removePrefix "/run/" (builtins.dirOf cfg.socket_path);
        StateDirectory = lib.removePrefix "/var/lib/" cfg.data_dir;
        ExecStart = "${lib.getBin cfg.package}/bin/spire-agent -c=${cfg.configFile}";
        Restart = "on-failure";
        ExecReload = "kill -HUP $MAINPID";
      };
    };
  };
}
