{ pkgs, config, ... }: {
  imports = [ ./default.nix ];

  services.nomad = {
    enable = true;
    client.enabled = true;

    datacenter = config.asg.region;

    plugin.rawExec.enabled = true;
  };
}
