{ self, lib, config, pkgs, nodeName, ... }:
let
  inherit (builtins) attrNames;
  inherit (lib) mkIf mkEnableOption;
  inherit (config.cluster) domain kms s3-bucket region instances;
  inherit (self.clusters.${config.cluster.name}) bitte-secrets-install;
in {
  options = {
    services.s3-download.enable = mkEnableOption "Download secrets from S3";
  };

  config = mkIf config.services.s3-download.enable {
    # TODO: add timer for doing this daily and restarting services
    #       alternatively switch to vault-agent after bootstrapping.
    systemd.services.s3-download = {
      description = "Download secrets from S3";
      after = [ "network-online.target" ];
      before = [ "vault.service" "consul.service" "nomad.service" ];
      requiredBy = [ "vault.service" "consul.service" "nomad.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "30s";
        RemainAfterExit = true;

        # ExecStartPost = let
        #   script = pkgs.writeShellScriptBin "s3-download-post" ''
        #     set -exuo pipefail
        #     systemctl reload consul || true
        #     systemctl reload vault || true
        #     systemctl reload nomad || true
        #   '';
        # in "${script}/bin/s3-download-post";
      };

      path = with pkgs; [ bitte-secrets-install ];

      script = let
        clientOrServer = if ((instances.${nodeName} or false) == false) then
          "client"
        else
          "server";
      in ''
        set -exuo pipefail

        bitte-secrets-install ${clientOrServer}
      '';
    };
  };
}
