{ self, pkgs, ... }: {
  imports = [
    ./common.nix
    ./docker.nix
    ./consul/client.nix
    ./vault/client.nix
    ./nomad/client.nix
  ];

  security.pki.certificateFiles =
    [ "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];

  boot.cleanTmpDir = true;

  # TODO: put our CA cert here.
  security.pki.certificates = [ ];
  time.timeZone = "UTC";
  networking.firewall.enable = false;
  systemd.services.amazon-init.enable = false;
  services.amazon-ssm-agent.enable = true;
}
