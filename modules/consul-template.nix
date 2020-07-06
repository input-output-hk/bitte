{ lib, pkgs, config, ... }:
let
  inherit (lib) mkOption mkIf mkMerge mapAttrsToList mkEnableOption;
  inherit (lib.types) submodule str package attrsOf bool enum attrs;

  cfg = config.services.consul-templates;

  templateType = submodule {
    options = {
      enable = mkOption {
        type = bool;
        default = true;
      };

      logLevel = mkOption {
        type = enum [ "debug" "info" "warn" "err" ];
        default = "info";
      };

      policies = mkOption {
        type = attrs;
        default = { };
      };

      source = mkOption {
        type = str;
        description = ''
          The template in https://golang.org/pkg/text/template/ syntax.
        '';
      };

      target = mkOption {
        type = str; # doesn't make much sense to have path type here i think.
        description = ''
          Path where the output of template application will end up.
        '';
      };
    };
  };

in {

  options.services.consul-templates = {
    enable = mkEnableOption "Enable consul-template services";

    package = mkOption {
      type = package;
      default = pkgs.consul-template;
    };

    templates = mkOption {
      type = attrsOf templateType;
      default = { };
    };
  };

  config.services.consul.policies = mkMerge (mapAttrsToList (name: value:
    let
      sourceFile = pkgs.writeText "${name}.tpl" value.source;
      ctName = "ct-${name}";
    in { ${ctName} = mkIf (cfg.enable && value.enable) value.policies; })
    cfg.templates);

  config.systemd.services = mkMerge (mapAttrsToList (name: value:
    let
      sourceFile = pkgs.writeText "${name}.tpl" value.source;
      ctName = "ct-${name}";
    in {
      ${ctName} = mkIf (cfg.enable && value.enable) {
        after = [
          "consul.service"
          "consul-policies.service"
          "network-online.target"
        ];
        wantedBy = [ "multi-user.target" ];
        requires = [ "network-online.target" ];

        serviceConfig = {
          DynamicUser = true;
          User = ctName;
          Group = "consul-policies"; # share /tmp to exchange tokens
          RuntimeDirectoryPreserve = "yes";
          StateDirectory = ctName;
          WorkingDirectory = "/var/lib/${ctName}";
          Restart = "on-failure";

          # ExecStartPre = let
          #   PATH = lib.makeBinPath (with pkgs; [ coreutils jq ] );
          #   execStartPre = pkgs.writeScript "${ctName}-start-pre" ''
          #     #!${pkgs.bash}/bin/bash
          #     PATH="${PATH}"
          #     id
          #     ls -la /var/lib/private/consul-policies/
          #     jq -r -e .SecretID < /tmp/${ctName}.secret.json > consul.token
          #   '';
          # in
          #   "+${execStartPre}";

          ExecStart = ''
            @${cfg.package}/bin/consul-template consul-template \
              -kill-signal SIGTERM \
              -consul-token "$(< /tmp/${ctName}.json)" \
              -log-level ${value.logLevel} \
              -template "${sourceFile}:${value.target}"'';

          ExecStartPost = "${pkgs.coreutils}/bin/rm -f ${value.target}";
        };
      };
    }) cfg.templates);
}
