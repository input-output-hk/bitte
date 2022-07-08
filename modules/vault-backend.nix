{ lib, config, pkgs, pkiFiles, ... }:
let
  cfg = config.services.vault-backend;
  deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
in {
  options = {
    services.vault-backend = {
      enable = lib.mkEnableOption "Enable the Terraform Vault Backend";

      debug = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      interface = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
      };

      port= lib.mkOption {
        type = lib.types.int;
        default = 8080;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [
      cfg.port
    ];

    systemd.services.vault-backend = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        VAULT_CACERT = "cert.pem";
        VAULT_URL = "https://vault.service.consul:8200";
        VAULT_PREFIX = "vbk"; # the prefix used when storing the secrets
        LISTEN_ADDRESS = "${cfg.interface}:${toString cfg.port}";
        DEBUG = lib.mkIf cfg.debug "TRUE";
      };

      serviceConfig = let
        certChainFile = if deployType == "aws" then pkiFiles.certChainFile
                        else pkiFiles.serverCertChainFile;
        certKeyFile = if deployType == "aws" then pkiFiles.keyFile
                      else pkiFiles.serverKeyFile;
        execStartPre = pkgs.writeBashBinChecked "vault-backend-pre" ''
          set -exuo pipefail
          export PATH="${lib.makeBinPath [ pkgs.coreutils ]}"

          cp ${certChainFile} cert.pem
          cp ${certKeyFile} key.pem
          chown --reference . --recursive .
        '';
      in {
        ExecStartPre = "!${execStartPre}/bin/vault-backend-pre";
        ExecStart = "${pkgs.vault-backend}/bin/vault-backend";

        DynamicUser = true;
        Group = "vault-backend";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = "read-only";
        ProtectSystem = "full";
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitBurst = 3;
        StateDirectory = "vault-backend";
        TimeoutStopSec = "30s";
        User = "vault-backend";
        WorkingDirectory = "/var/lib/vault-backend";
      };
    };
  };
}
