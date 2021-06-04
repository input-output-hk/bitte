{ lib, pkgs, config, nodeName, ... }:
let inherit (config.cluster) instances region;
in {
  config = lib.mkIf config.services.consul.enable {
    age.secrets = {
      consul-encrypt = {
        file = ../../encrypted/consul/encrypt.age;
        path = "/etc/consul.d/encrypt.json";
        mode = "0444";
        script = ''
          echo '{}' \
            | ${pkgs.jq}/bin/jq \
              --arg encrypt "$(< "$src")" \
              '.encrypt = $encrypt' \
            > $out
        '';
      };

      consul-token-master = let
        base.acl = {
          default_policy = "deny";
          down_policy = "extend-cache";
          enable_token_persistence = true;
          enabled = true;
        };
      in {
        file = ../../encrypted/consul/token-master.age;
        path = "/etc/consul.d/token-master.json";
        mode = "0444";
        script = ''
          echo '${builtins.toJSON base}' \
            | ${pkgs.jq}/bin/jq \
              --arg token "$(< "$src")" \
              '.acl.tokens.master = $token' \
            > $out
        '';
      };

      consul-ca = {
        file = ../../encrypted/ssl/ca.age;
        path = "/var/lib/consul/ca.pem";
      };

      consul-server = {
        file = ../../encrypted/ssl/server.age;
        path = "/var/lib/consul/server.pem";
      };

      consul-server-key = {
        file = ../../encrypted/ssl/server-key.age;
        path = "/var/lib/consul/server-key.pem";
      };
    };

    services.consul = {
      clientAddr = "0.0.0.0";
      datacenter = region;
      enableLocalScriptChecks = true;
      logLevel = "trace";
      primaryDatacenter = region;
      tlsMinVersion = "tls12";
      verifyIncoming = true;
      verifyOutgoing = true;
      verifyServerHostname = true;

      caFile = "/var/lib/consul/ca.pem";
      certFile = "/var/lib/consul/server.pem";
      keyFile = "/var/lib/consul/server-key.pem";

      telemetry = {
        dogstatsdAddr = "localhost:8125";
        disableHostname = true;
      };

      nodeMeta = {
        inherit region;
        inherit nodeName;
      } // (lib.optionalAttrs ((instances.${nodeName} or null) != null) {
        inherit (instances.${nodeName}) domain;
      });

      # generate deterministic UUIDs for each node so they can rejoin.
      nodeId = lib.mkIf (config.instance != null) (lib.fileContents
        (pkgs.runCommand "node-id" { buildInputs = [ pkgs.utillinux ]; }
          "uuidgen -s -n ab8c189c-e764-4103-a1a8-d355b7f2c814 -N ${nodeName} > $out"));

      bindAddr = lib.mkDefault ''{{ GetInterfaceIP "ens5" }}'';

      advertiseAddr = lib.mkDefault ''{{ GetInterfaceIP "ens5" }}'';

      retryJoin = lib.mapAttrsToList (_: v: v.privateIP) instances;

      connect = {
        enabled = true;
        caProvider = "consul";
      };

      ports = {
        grpc = 8502;
        https = 8501;
        http = 8500;
      };

      extraConfig = {
        configEntries = [{
          bootstrap = [{
            kind = "proxy-defaults";
            name = "global";
            config = [{ protocol = "http"; }];
            meshGateway = [{ mode = "local"; }];
          }];
        }];
      };
    };

    services.dnsmasq = {
      enable = true;
      extraConfig = ''
        # Ensure docker0 is also bound on client machines when it may not exist during dnsmasq startup:
        # - This ensures nomad docker driver jobs have dnsmasq access
        # - This enables nomad exec driver bridge mode jobs to use the docker bridge for dnsmasq access
        #   when explicitly defined as a nomad network dns server ip
        bind-dynamic

        # Redirect consul and ec2 internal specific queries to their respective upstream DNS servers
        server=/consul/127.0.0.1#8600
        server=/internal/169.254.169.253#53

        # Configure reverse in-addr.arpa DNS lookups to consul for ASGs and core datacenter default address ranges
        rev-server=10.0.0.0/8,127.0.0.1#8600
        rev-server=172.16.0.0/16,127.0.0.1#8600

        # Define upstream DNS servers
        server=169.254.169.253
        server=8.8.8.8

        # Set cache and security
        cache-size=65536
        local-service
      '';
    };

    # Restarts automatically upon fail, ex: memory limit hit
    systemd.services.dnsmasq.startLimitIntervalSec = 0;
    systemd.services.dnsmasq.serviceConfig.RestartSec = "1s";
    systemd.services.dnsmasq.serviceConfig.MemoryMax = "128M";

    # Used for Consul Connect and requires reboot?
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-arptables" = lib.mkDefault 1;
      "net.bridge.bridge-nf-call-ip6tables" = lib.mkDefault 1;
      "net.bridge.bridge-nf-call-iptables" = lib.mkDefault 1;
    };
  };
}
