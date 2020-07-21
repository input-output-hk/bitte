{ lib, ... }:
lib.flip lib.pipe [
  (builtins.split "([^a-z])")
  (lib.concatMapStrings (s: if builtins.isList s then "_${toString s}" else s))
  lib.toLower
]
