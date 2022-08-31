{lib, ...}: let
  inherit (lib) mkDefault;
in {
  imports = [
    # Profiles -- ungated config mutation w/o options
    ./common.nix
    ./consul/client.nix
    ./vault/monitoring.nix
    ./auxiliaries/loki.nix

    # Modules -- enable gated config mutation w/ options
    ../modules/grafana.nix
    ../modules/monitoring.nix
    ../modules/tempo.nix
  ];

  services.monitoring.enable = mkDefault true;
  services.loki.enable = mkDefault true;
  services.tempo.enable = mkDefault true;
  services.minio.enable = mkDefault true;

  services.nomad.enable = false;
}
