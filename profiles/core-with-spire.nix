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
    spire-agent.enable = true;
  };
}
