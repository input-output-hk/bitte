{...}: {
  imports = [
    # Profiles -- ungated config mutation w/o options
    ./common.nix
    ./consul/client.nix
    ./vault/monitoring.nix
    ./auxiliaries/loki.nix

    # Modules -- enable gated config mutation w/ options
    ../modules/monitoring.nix
  ];

  services.monitoring.enable = true;
  services.loki.enable = true;
  services.minio.enable = true;

  services.nomad.enable = false;
}
