{ self, pkgs, lib, system, config, ... }:
let inherit (lib) mkIf mkOption mkOptionType;
in {
  options = {
    terraform-output =
      mkOption { type = mkOptionType { name = "config.tf.json"; }; };
  };

  config = mkIf (config.terraform != { }) {
    terraform-output = let
      terraform-config = import (self.inputs.terranix + "/core/default.nix") {
        pkgs = self.inputs.nixpkgs.legacyPackages.x86_64-linux;
        strip_nulls = false;
        terranix_config = { imports = [ config.terraform ]; };
      };

      mini-json = pkgs.writeText "config.tf.mini.json"
        (builtins.toJSON terraform-config.config);

      pretty-json = pkgs.runCommandNoCCLocal "config.tf.json" { } ''
        ${pkgs.jq}/bin/jq -S < ${mini-json} > $out
      '';
    in pretty-json;
  };
}
