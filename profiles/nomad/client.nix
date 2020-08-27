{ pkgs, config, ... }: {
  imports = [ ./default.nix ];

  services.nomad = {
    enable = true;
    client.enabled = true;

    datacenter = config.asg.region;

    plugin.raw_exec.enabled = true;

    client.chroot_env = {
      "/usr/bin/env" = "/usr/bin/env";
      "/nix/store" = "/nix/store";
    };
  };
}
