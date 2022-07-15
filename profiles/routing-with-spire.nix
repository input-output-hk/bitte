{
  self,
  pkgs,
  config,
  lib,
  nodeName,
  ...
}: {
  imports = [./routing.nix];
  services = {
    spire-agent.enable = true;
  };
}
