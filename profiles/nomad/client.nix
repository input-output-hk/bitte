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
        "/etc/passwd" = "/etc/passwd";
      };
    };

    datacenter = config.asg.region;

    plugin.raw_exec.enabled = false;

    vault.address = "http://127.0.0.1:8200";
  };

  systemd.services.nomad.environment = {
    CONSUL_HTTP_ADDR = "http://127.0.0.1:8500";
  };

  system.extraDependencies = [ pkgs.pkgsStatic.busybox ];

  users.extraUsers.nobody.isSystemUser = true;
  users.groups.nogroup = { };
}
