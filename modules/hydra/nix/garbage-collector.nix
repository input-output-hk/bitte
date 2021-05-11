{ pkgs, config, lib, ... }:
let
  cfg = config.nix.gc;
in {
  options.nix.gc = {
    autoMaxFreedGB = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "An absolute amount to free at";
    };

    autoMinFreeGB = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "The minimum amount to trigger a GC at";
    };

    absoluteTimedGB = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "The max absolute level to free to on the /nix/store mount for the timed GC";
    };
  };

  config.nix = lib.mkIf cfg.automatic {
    gc = {
      # Set the max absolute level to free to absoluteTimedGB on the /nix/store mount
      options = ''--max-freed "$((${toString cfg.absoluteTimedGB} * 1024**3 - 1024 * $(df -P -k /nix/store | tail -n 1 | ${pkgs.gawk}/bin/awk '{ print $4 }')))"'';
    };

    # This GC is run automatically by nix-build
    extraOptions = ''
      # Try to ensure between ${toString cfg.autoMinFreeGB}G and ${toString cfg.autoMaxFreedGB}G of free space by
      # automatically triggering a garbage collection if free
      # disk space drops below a certain level during a build.
      min-free = ${toString (cfg.autoMinFreeGB * 1024 * 1024 * 1024)}
      max-free = ${toString (cfg.autoMaxFreedGB * 1024 * 1024 * 1024)}
    '';
  };
}
