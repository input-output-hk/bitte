{ lib, self, ... }: {
  services = {
    openssh = {
      enable = true;
      passwordAuthentication = false;
    };
  };

  users.extraUsers.root.openssh.authorizedKeys.keys = let
    ssh-keys = let
      keys = import (self.ops-lib + "/overlays/ssh-keys.nix") lib;
      inherit (keys) allKeysFrom devOps;
    in { devOps = allKeysFrom devOps; };
  in ssh-keys.devOps;
}
