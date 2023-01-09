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

    command.text =
      ''
        nix flake check --allow-import-from-derivation --no-build
      ''
      + config.preset.github.status.lib.reportBulk {
        bulk.text = ''
          nix eval .#checks --apply __attrNames --json |
          nix-systems -i |
          jq 'with_entries(select(.value))' # filter out systems that we cannot build for
        '';
        each.text = ''
          IFS=$'\n'
          for drv in $(nix eval .#checks."$1" --apply __attrNames --json | jq -r .[]); do
            nix build -L .#checks."$1"."$drv"
          done
        '';
      };

    memory = 1024 * 12;

    nomad = {
      resources.cpu = 10000;

      driver = "exec";
    };
  };
}
