{
  self,
  pkgs,
  config,
  lib,
  nodeName,
  ...
}: {
  imports = [./core.nix];
  services = {
    spire-server.enable = true;
    spire-agent.enable = true;
  };
}
