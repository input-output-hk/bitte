{ self, config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkEnableOption;
  inherit (config) cluster;
  inherit (config.cluster) s3-bucket kms;
in {
  options = {
    services.s3-upload.enable = mkEnableOption "Upload flake to S3";
  };

  config = mkIf config.services.s3-upload.enable {

    systemd.services.s3-upload = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = "30s";
      };

      path = with pkgs; [ awscli xz gnutar coreutils ];

      script = ''
        tar cvf source.tar.xz -C ${self.outPath} .
        aws s3 cp \
          source.tar.xz \
          "s3://${s3-bucket}/infra/secrets/${cluster.name}/${kms}/source/source.tar.xz"
      '';
    };
  };
}
