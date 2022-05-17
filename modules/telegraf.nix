{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.telegraf;

  preScript = pkgs.writeBashBinChecked "telegraf-start-pre" ''
    mkdir -p /etc/telegraf

    ${pkgs.jq}/bin/jq \
      < ${pkgs.writeText "config.json" (builtins.toJSON (lib.recursiveUpdate cfg.extraConfig cfg.overrides))} \
      --arg host "$(${pkgs.nettools}/bin/hostname)" '.global_tags.hostname = $host' \
      | ${pkgs.remarshal}/bin/remarshal -if json -of toml \
      > /etc/telegraf/config.toml
  '';
in {
  ###### interface
  disabledModules = [ "services/monitoring/telegraf.nix" ];
  options = {
    services.telegraf = {
      enable = mkEnableOption "telegraf server";

      package = mkOption {
        default = pkgs.telegraf;
        defaultText = "pkgs.telegraf";
        description = "Which telegraf derivation to use";
        type = types.package;
      };

      extraConfig = mkOption {
        default = { };
        description = "Extra configuration options for telegraf";
        type = types.attrs;
        example = {
          outputs = {
            influxdb = {
              urls = [ "http://localhost:8086" ];
              database = "telegraf";
            };
          };
          inputs = {
            statsd = {
              service_address = ":8125";
              delete_timings = true;
            };
          };
        };
      };

      # TODO: There is probably a better way to do this
      overrides = mkOption {
        default = { };
        description = "An overrides attr to allow better attr merge support to extraConfig";
        type = types.attrs;
      };
    };
  };

  ###### implementation
  config = mkIf cfg.enable {
    systemd.services.telegraf = {
      description = "Telegraf Agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStartPre = "!${preScript}/bin/telegraf-start-pre";
        ExecStart =
          "${cfg.package}/bin/telegraf -config /etc/telegraf/config.toml";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        User = "telegraf";
        Restart = "on-failure";
      };
    };

    users.users.telegraf = {
      group = "telegraf";
      uid = config.ids.uids.telegraf;
      description = "telegraf daemon user";
    };

    users.groups.telegraf = { };
  };
}
