let
  inherit (builtins) readFile fromJSON;

  lock = fromJSON (readFile ./flake.lock);
  pkgsInfo = lock.nodes.nixpkgs.locked;
  src = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${pkgsInfo.rev}.tar.gz";
  };
in with import src {}; mkShell { buildInputs = [ nixFlakes ]; }
