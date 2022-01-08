{ self, pkgs, config, lib, nodeName, ... }: {
  imports = [ ./client.nix ];
  services = {
    spire-agent.enable = true;
  };
}
