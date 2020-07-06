{ pkgs, ... }: {
  services = {
    openssh = {
      enable = true;
      passwordAuthentication = false;
    };
  };

  users.extraUsers.root.openssh.authorizedKeys.keys = pkgs.ssh-keys.devOps;
}
