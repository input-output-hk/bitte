{ self, config, lib, pkgs, ... }: {
  options = {
    services.s3-upload-flake.enable = lib.mkEnableOption ''
      Upload latest flake of this auto scaling group to S3
      for a userData-mediated unsupervised boot into thek
      correct nixos version of a scaling client instance.
    '';
  };

  config = lib.mkIf config.services.s3-upload-flake.enable {

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
        tar cvf source.tar.xz -C ${config.cluster.flakePath} .
        aws s3 cp \
          source.tar.xz \
          "s3://${config.cluster.s3Bucket}/infra/secrets/${config.cluster.name}/${config.cluster.kms}/source/${config.currentAwsAutoScalingGroup.name}-source.tar.xz"
      '';
    };
  };
}
