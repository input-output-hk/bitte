{ lib, config, ... }: let
  failedAssertions =
    map (x: x.message) (lib.filter (x: !x.assertion) config.assertions);
  validateConfig = if failedAssertions != [ ] then
    throw ''

      Failed assertions:
      ${builtins.concatStringsSep "\n"
      (map (x: "- ${x}") failedAssertions)}''
  else
    lib.showWarnings config.warnings;
in {
  options.showWarningsAndAssertions = lib.mkOption {
    type = with lib.types; bool;
    default = validateConfig true;
  };
}
