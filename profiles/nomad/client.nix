{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ./common.nix ./nomad/bridge-lo-fixup.nix ]; };

  Switches = {
    services.nomad.client.enable = true;
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

      plugin.raw_exec.enabled = false;

      vault.address = "http://127.0.0.1:8200";
    };

    systemd.services.nomad.environment = {
      CONSUL_HTTP_ADDR = "http://127.0.0.1:8500";
    };

    system.extraDependencies = [ pkgs.pkgsStatic.busybox ];

    users.extraUsers.nobody.isSystemUser = true;
    users.groups.nogroup = { };
  };

in lib.mkMerge [
  Imports
  Switches
  Config
]
