{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ./common.nix ./bridge-lo-fixup.nix ]; };

  Switches = {
    services.nomad.client.enabled = true;
    services.nomad.plugin.raw_exec.enabled = false;
  };

  Config = {
    services.nomad = {
      client = {
        gc_interval = "12h";
        node_class =
          if config.currentAwsAutoScalingGroup.node_class != null then config.currentAwsAutoScalingGroup.node_class else "core";
        chroot_env = {
          # "/usr/bin/env" = "/usr/bin/env";
          "${builtins.unsafeDiscardStringContext pkgs.pkgsStatic.busybox}" =
            "/usr";
          "/etc/passwd" = "/etc/passwd";
        };
      };

      datacenter = config.currentAwsAutoScalingGroup.region;

      vault.address = "http://127.0.0.1:8200";
    };

    systemd.services.nomad.environment = {
      CONSUL_HTTP_ADDR = "http://127.0.0.1:8500";
    };

    system.extraDependencies = [ pkgs.pkgsStatic.busybox ];

    users.extraUsers.nobody.isSystemUser = true;
    users.groups.nogroup = { };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
