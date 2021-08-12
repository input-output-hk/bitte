{ pkgs, ... }: {
  imports = [ ./secrets.nix ];

  disabledModules = [ "virtualisation/amazon-image.nix" ];

  services.ssm-agent.enable = true;

  nix = {
    binaryCaches = [ config.cluster.aws.s3Cache ];
    binaryCachePublicKeys = [ config.cluster.aws.s3CachePubKey ];
  };

  networking = {
    firewall.enable = false;
    hostId = "9474d585";
  };

  boot = {
    cleanTmpDir = true;
    loader.grub.device = lib.mkForce "/dev/nvme0n1";
  };

  environment.systemPackages = with pkgs; [ awscli ];
}
