{ bitte, lib, ... }: {
  services = {
    openssh = {
      enable = true;
      passwordAuthentication = false;
    };
  };

  users.extraUsers.root.openssh.authorizedKeys.keys = let
    ssh-keys = let
      keys = import (bitte.inputs.ops-lib + "/overlays/ssh-keys.nix") lib;
      inherit (keys) allKeysFrom devOps;
    in { devOps = allKeysFrom devOps; };
  in ssh-keys.devOps;
}
