{ lib }:
pkgs: services:
let
  checks = lib.concatStringsSep "\n" (lib.forEach services
    (service: "${pkgs.systemd}/bin/systemctl is-active '${service}.service'"));
in pkgs.writeShellScript "check" ''
  set -exuo pipefail
  ${checks}
''
