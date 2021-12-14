{ lib, pkgs, config, ... }:
let
  cfg = config.services.consul-templates;

  templateType = with lib.types; submodule {
    options = {
      enable = lib.mkOption {
        type = with lib.types; bool;
        default = true;
      };

      logLevel = lib.mkOption {
        type = with lib.types; enum [ "debug" "info" "warn" "err" ];
        default = "info";
      };

      policies = lib.mkOption {
        type = with lib.types; attrs;
        default = { };
      };

      source = lib.mkOption {
        type = with lib.types; str;
        description = ''
          The template in https://golang.org/pkg/text/template/ syntax.
        '';
      };

      target = lib.mkOption {
        type = with lib.types;
          str; # doesn't make much sense to have path type here i think.
        description = ''
          Path where the output of template application will end up.
        '';
      };
    };
  };

in {

  options.services.consul-templates = {
    enable = lib.mkEnableOption "Enable consul-template services";

    package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.consul-template;
    };

    templates = lib.mkOption {
      type = with lib.types; attrsOf templateType;
      default = { };
    };
  };

  config.services.consul.policies = lib.mkMerge (lib.mapAttrsToList
    (name: value:
      let
        sourceFile = pkgs.writeText "${name}.tpl" value.source;
        ctName = "ct-${name}";
      in { ${ctName} = lib.mkIf (cfg.enable && value.enable) value.policies; })
    cfg.templates);

  config.systemd.services = lib.mkMerge (lib.mapAttrsToList (name: value:
    let
      sourceFile = pkgs.writeText "${name}.tpl" value.source;
      ctName = "ct-${name}";
    in {
      ${ctName} = lib.mkIf (cfg.enable && value.enable) {
        after =
          [ "consul.service" "consul-acl.service" "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        requires = [ "network-online.target" ];

        serviceConfig = {
          DynamicUser = true;
          User = ctName;
          Group = "consul-acl"; # share /tmp to exchange tokens
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
          #     ls -la /var/lib/private/consul-acl/
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
