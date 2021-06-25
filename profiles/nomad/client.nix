{ pkgs, config, nodeName, ... }: {
  imports = [ ./default.nix ];

  services.nomad = {
    enable = true;

    client = {
      enabled = true;
      gc_interval = "12h";
      chroot_env = let
        busybox = builtins.unsafeDiscardStringContext pkgs.pkgsStatic.busybox;
      in {
        "${busybox}" = "/usr";
        "/etc/passwd" = "/etc/passwd";
      };
    };

    datacenter = config.cluster.instances.${nodeName}.datacenter;

    plugin.raw_exec.enabled = false;

    vault.address = "http://active.vault.service.consul:8200";
  };

  system.extraDependencies = [ pkgs.pkgsStatic.busybox ];

  users.extraUsers.nobody.isSystemUser = true;
  users.groups.nogroup = { };
}
