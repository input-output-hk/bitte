{ config, lib, pkgs, pkiFiles, ... }: let

  Imports = { imports = [
    ./common.nix

    ./secrets-provisioning/hashistack.nix
    ./secrets-provisioning/host-identity.nix
  ]; };

  Switches = {
    services.vault-agent.disableTokenRotation.consulAgent = true;
    services.vault-agent.disableTokenRotation.consulDefault = true;
  };

  Config = let
    deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
    domain = config.${if deployType == "aws" then "cluster" else "currentCoreNode"}.domain;
  in {
    services.vault-agent = {
      role = "client";
      vaultAddress = "https://vault.${domain}"; # avoid depending on consul
      cache.useAutoAuthToken = true;
      listener = [{
          type = "tcp";
          address = "172.17.0.1:8200";
          tlsDisable = true;
      }];
    };

    systemd.services.certs-updated = lib.mkIf (deployType == "aws") {
      wantedBy = [ "multi-user.target" ];
      after = [ "vault-agent.service" ];
      path = with pkgs; [ coreutils curl systemd ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
      };

      script = ''
        set -exuo pipefail

        test -f /etc/ssl/certs/.last_restart || touch -d '2020-01-01' /etc/ssl/certs/.last_restart
        [ -f ${pkiFiles.caCertFile} ]
        [ ${pkiFiles.certChainFile} -nt /etc/ssl/certs/.last_restart ]
        [ ${pkiFiles.certFile} -nt /etc/ssl/certs/.last_restart ]
        [ ${pkiFiles.keyFile} -nt /etc/ssl/certs/.last_restart ]

        systemctl try-reload-or-restart consul.service

        if curl -s -k https://127.0.0.1:4646/v1/status/leader &> /dev/null; then
          systemctl try-reload-or-restart nomad.service
        else
          systemctl start nomad.service
        fi

        touch /etc/ssl/certs/.last_restart
      '';
    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
