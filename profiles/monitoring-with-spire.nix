{
  self,
  pkgs,
  config,
  lib,
  nodeName,
  ...
}: {
  imports = [./monitoring.nix];
  services = {
    spire-agent.enable = true;
  };
}
