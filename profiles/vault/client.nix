{
  config,
  lib,
  pkgs,
  pkiFiles,
  ...
}: let
  Imports = {
    imports = [
      ./common.nix
    ];
  };

  Switches = {
    services.vault-agent.disableTokenRotation.consulAgent = true;
    services.vault-agent.disableTokenRotation.consulDefault = true;
  };

  Config = let
    deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
    domain =
      config
      .${
        if builtins.elem deployType ["aws" "awsExt"]
        then "cluster"
        else "currentCoreNode"
      }
      .domain;
  in {
    services.vault-agent = {
      role = "client";
      # if we use aws and consul depends on vault bootstrapping (get a token)
      # then we cannot depend on consul to access vault, obviously
      vaultAddress =
        if builtins.elem deployType ["aws" "awsExt"]
        then "https://vault.${domain}"
        else "https://core.vault.service.consul:8200";
      cache.useAutoAuthToken = true;
      # Commit 248791a: Binds vault agent to docker bridge for bridge net access
      listener = [
        {
          type = "tcp";
          address = "172.17.0.1:8200";
          tlsDisable = true;
        }
      ];
    };

    systemd.services.certs-updated = {
      wantedBy = ["multi-user.target"];
      after = ["vault-agent.service"];
      path = with pkgs; [coreutils curl systemd];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "20s";
      };

      script = ''
        set -exuo pipefail

        test -f /etc/ssl/certs/.last_restart || touch -d '2020-01-01' /etc/ssl/certs/.last_restart
        if ! [ -f ${pkiFiles.caCertFile} ]; then
          echo "Waiting to start, restart or reload services since ${pkiFiles.caCertFile} doesn't exist yet"
          exit 1
        fi

        if [ ${pkiFiles.certChainFile} -ot /etc/ssl/certs/.last_restart ]; then
          echo "Waiting to start, restart or reload services since ${pkiFiles.certChainFile} is still older than the last restart"
          exit 1
        fi

        if [ ${pkiFiles.certFile} -ot /etc/ssl/certs/.last_restart ]; then
          echo "Waiting to start, restart or reload services since ${pkiFiles.certFile} is still older than the last restart"
          exit 1
        fi

        if [ ${pkiFiles.keyFile} -ot /etc/ssl/certs/.last_restart ]; then
          echo "Waiting to start, restart or reload services since ${pkiFiles.keyFile} is still older than the last restart"
          exit 1
        fi

        if systemctl is-enabled consul.service &> /dev/null; then
          systemctl try-reload-or-restart consul.service
        else
          echo "Skipping consul reload or restart as consul is disabled in systemd services."
        fi

        if systemctl is-enabled nomad.service &> /dev/null; then
          if curl -s -k https://127.0.0.1:4646/v1/status/leader &> /dev/null; then
            systemctl try-reload-or-restart nomad.service
          else
            systemctl start nomad.service
          fi
        else
          echo "Skipping nomad reload, restart or start as nomad is disabled in systemd services."
        fi

        touch /etc/ssl/certs/.last_restart
      '';
    };
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
