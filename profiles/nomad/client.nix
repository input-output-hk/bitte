{ pkgs, ... }: {
  imports = [ ./default.nix ];

  services.nomad = {
    enable = true;
    client.enabled = true;
    plugin = [{ rawExec = [{ config = [{ enabled = true; }]; }]; }];
  };
}
