{ lib, pkgs, config, nodeName, ... }:
let
  inherit (lib) mapAttrsToList mkIf mkDefault;
  inherit (config.cluster) instances region;
in {
  services.consul = mkIf config.services.consul.enable {
    addresses = { http = mkDefault "127.0.0.1"; };

    clientAddr = "0.0.0.0";
    datacenter = region;
    enableLocalScriptChecks = true;
    logLevel = "trace";
    primaryDatacenter = region;
    tlsMinVersion = "tls12";
    verifyIncoming = true;
    verifyOutgoing = true;
    verifyServerHostname = true;

    caFile = "/etc/ssl/certs/full.pem";
    certFile = "/etc/ssl/certs/cert.pem";
    keyFile = "/var/lib/consul/cert-key.pem";

    telemetry = {
      dogstatsdAddr = "localhost:8125";
      disableHostname = true;
    };

    nodeMeta = {
      inherit region;
      inherit nodeName;
    } // (lib.optionalAttrs ((instances.${nodeName} or null) != null) {
      inherit (instances.${nodeName}) instanceType domain;
    });

    bindAddr = ''{{ GetInterfaceIP "ens5" }}'';

    advertiseAddr = ''{{ GetInterfaceIP "ens5" }}'';

    retryJoin = (mapAttrsToList (_: v: v.privateIP) instances)
      ++ [ "provider=aws region=${region} tag_key=Consul tag_value=server" ];

    acl = {
      enabled = true;
      defaultPolicy = "deny";
      enableTokenPersistence = true;
      downPolicy = "extend-cache";
    };

    connect = {
      enabled = true;
      caProvider = "consul";
    };

    ports = {
      grpc = 8502;
      https = 8501;
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
      server=/consul/127.0.0.1#8600
      rev-server=10.0.0.0/8,127.0.0.1#8600
      rev-server=127.0.0.1/8,127.0.0.1#8600
      local-service
      server=169.254.169.253
      server=8.8.8.8
      cache-size=65536
    '';
  };

  # Used for Consul Connect and requires reboot?
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-arptables" = mkDefault 1;
    "net.bridge.bridge-nf-call-ip6tables" = mkDefault 1;
    "net.bridge.bridge-nf-call-iptables" = mkDefault 1;
  };
}
