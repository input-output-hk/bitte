{ lib, pkgs, config, nodeName, ... }:
let
  inherit (lib) mapAttrsToList;
  inherit (config.cluster) instances region;
  instance = instances.${nodeName};
  inherit (instance) privateIP;
in {
  imports = [ ./default.nix ./policies.nix ];

  services.consul = {
    bootstrapExpect = 3;
    addresses = { http = "${privateIP} 127.0.0.1"; };
    # autoEncrypt = {
    #   allowTls = true;
    #   tls = true;
    # };
    enable = true;
    server = true;
    ui = true;

    # generate deterministic UUIDs for each node so they can rejoin.
    nodeId = lib.fileContents
      (pkgs.runCommand "node-id" { buildInputs = [ pkgs.utillinux ]; }
        "uuidgen -s -n ab8c189c-e764-4103-a1a8-d355b7f2c814 -N ${nodeName} > $out");
  };
}
