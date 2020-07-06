{ lib, pkgs, config, ... }:
let
  inherit (config.cluster) region instances;
  inherit (lib) mkIf mapAttrsToList;
in {
  imports = [ ./default.nix ];

  services.nomad = {
    enable = true;

    server = {
      enabled = true;

      bootstrapExpect = 3;
      # TODO: make dynamic
      encrypt = "abv4BWoClT47x7Kwh6U9EQ==";

      serverJoin = {
        retryJoin = (mapAttrsToList (_: v: v.privateIP) instances)
          ++ [ "provider=aws region=${region} tag_key=Nomad tag_value=server" ];
      };
    };
  };
}
