{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [ ./core.nix ];
  services = {
    spire-server.enbale = true;
    spire-agent.enable = true;
  };
}
