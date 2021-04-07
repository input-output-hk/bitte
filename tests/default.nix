{ lib, pkgs, ... }:
{
  testNomadAutoScaler = pkgs.nixosTest {
    name = "nomad-autoscaler";

    machine = { ... }: {
      imports = [ ../modules/nomad-autoscaler.nix ];

      services.nomad-autoscaler.enable = true;
    };

    testScript = ''
      machine.systemctl("is-system-running --wait")
    '';
  };
}
