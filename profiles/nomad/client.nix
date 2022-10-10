{
  config,
  lib,
  pkgs,
  nomad-driver-nix,
  dockerAuth,
  ...
}: let
  Imports = {imports = [./common.nix ./bridge-lo-fixup.nix];};

  Switches = {
    services.nomad.client.enabled = true;
    services.nomad.plugin.raw_exec.enabled = false;
    services.nomad.plugin.nix-driver.enabled = true;
  };

  Config = let
    deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
    datacenter = config.currentCoreNode.datacenter or config.cluster.region;
    cfg = config.services.nomad;
  in {
    # Nomad firewall references:
    #   https://www.nomadproject.io/docs/install/production/requirements
    #
    # Nomad ports specific to clients
    networking.firewall = {
      allowedTCPPortRanges = [
        {
          from = cfg.client.min_dynamic_port;
          to = cfg.client.max_dynamic_port;
        }
      ];

      # Trust traffic originating from the Nomad bridge where nomad bridge jobs are run
      trustedInterfaces = [cfg.client.bridge_network_name];
    };

    # Used for Consul Connect in clients
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-arptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
    };

    services.nomad = {
      pluginDir = "${nomad-driver-nix.defaultPackage.x86_64-linux}/bin";
      plugin.docker.auth.config = dockerAuth;

      client = {
        gc_interval = "12h";
        node_class =
          config
          .${
            if builtins.elem deployType ["aws" "awsExt"]
            then "currentAwsAutoScalingGroup"
            else "currentCoreNode"
          }
          .node_class
          or "core";
        chroot_env = {
          # "/usr/bin/env" = "/usr/bin/env";
          "${builtins.unsafeDiscardStringContext pkgs.pkgsStatic.busybox}" = "/usr";
          "/etc/passwd" = "/etc/passwd";
          "/etc/resolv.conf" = "/etc/resolv.conf";
          "/etc/ssl/certs/ca-bundle.crt" = "/etc/ssl/certs/ca-bundle.crt";
          "/etc/ssl/certs/ca-certificates.crt" = "/etc/ssl/certs/ca-certificates.crt";
        };

        # min_dynamic_port adjusted higher than the 20000 default to avoid collision
        # with consul's dynamic port range.
        #
        # Refs:
        #   https://www.nomadproject.io/docs/job-specification/network#dynamic-ports
        #   https://www.consul.io/docs/agent/options#ports
        #   https://github.com/hashicorp/consul/issues/12253
        #   https://github.com/hashicorp/nomad/issues/4285
        min_dynamic_port = 22000;
        max_dynamic_port = 32000;
      };

      datacenter =
        if builtins.elem deployType ["aws"]
        then config.currentAwsAutoScalingGroup.region
        else datacenter;

      vault.address = "http://127.0.0.1:8200";
    };

    systemd.services.nomad.environment = {
      CONSUL_HTTP_ADDR = "http://127.0.0.1:8500";
    };

    system.extraDependencies = [pkgs.pkgsStatic.busybox];

    users.extraUsers.nobody.isSystemUser = true;
    users.groups.nogroup = {};
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
