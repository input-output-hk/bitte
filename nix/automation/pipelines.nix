{
  cell,
  inputs,
}: let
  ciInputName = "GitHub event";
in {
  build = {
    config,
    lib,
    ...
  }: {
    preset = {
      nix.enable = true;

      github.ci = __mapAttrs (_: lib.mkDefault) {
        enable = config.actionRun.facts != {};
        repository = "input-output-hk/bitte";
        remote = config.preset.github.lib.readRepository ciInputName null;
        revision = config.preset.github.lib.readRevision ciInputName null;
      };
    };

    command.text = ''
      set -x
      nix flake check --allow-import-from-derivation
    '';

    memory = 1024 * 12;

    nomad = {
      resources.cpu = 10000;

      driver = "exec";
    };
  };
}
