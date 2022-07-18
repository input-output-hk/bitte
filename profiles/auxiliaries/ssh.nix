{pkgs, ...}: {
  services.openssh.enable = true;
  services.openssh.passwordAuthentication = false;

  users.extraUsers.root.openssh.authorizedKeys.keys = pkgs.ssh-keys.devOps;
}
