{rev ? "HEAD", ...}: let
  common = {
    config,
    lib,
    ...
  }: {
    preset = {
      nix.enable = true;
      github-ci = __mapAttrs (_: lib.mkDefault) {
        enable = config.action.facts != {};
        repo = "input-output-hk/bitte";
        sha = config.preset.github-ci.lib.getRevision "GitHub event" rev;
        clone = false;
      };
    };
  };

  flakeUrl = {
    config,
    lib,
    ...
  }:
    lib.escapeShellArg (
      if config.action.facts != {}
      then "github:${config.preset.github-ci.repo}/${config.preset.github-ci.lib.getRevision "GitHub event" rev}"
      else "."
    );
in {
  build = args: {
    imports = [common];

    config = {
      command.text = ''
        echo "Running flake check on ${flakeUrl args}"
        nix flake check --allow-import-from-derivation ${flakeUrl args}
      '';

      preset.github-ci.clone = true;
      memory = 1024 * 12;
      nomad.resources.cpu = 10000;
    };
  };
}
