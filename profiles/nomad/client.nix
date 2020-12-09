{ pkgs, config, ... }: {
  imports = [ ./default.nix ];

  services.nomad = {
    enable = true;

    client = {
      enabled = true;
      gc_interval = "12h";
      chroot_env = {
        # "/usr/bin/env" = "/usr/bin/env";
        "${builtins.unsafeDiscardStringContext pkgs.pkgsStatic.busybox}" =
          "/usr";
      };
    };

    datacenter = config.asg.region;

    plugin.raw_exec.enabled = false;

    vault.address = "https://127.0.0.1:8200";
  };

  system.extraDependencies = [ pkgs.pkgsStatic.busybox ];

  users.extraUsers.nobody.isSystemUser = true;
  users.groups.nogroup = { };
}
