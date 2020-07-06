let
  inherit (builtins) readFile fromJSON;

  # This basically gets the correct version of nixFlakes from the flake nixpkgs
  # from the so you can enter a nix-shell to build it.

  lock = fromJSON (readFile ./flake.lock);
  pkgsInfo = lock.nodes.nixpkgs.locked;
  src = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${pkgsInfo.rev}.tar.gz";
  };
in with import src { }; mkShell { buildInputs = [ nixFlakes ]; }
