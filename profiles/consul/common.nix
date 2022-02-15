{ lib, pkgs, config, nodeName, pkiFiles, ... }: let

  Imports = { imports = [ ]; };

  Switches = {
    services.consul.enable = true;
    services.consul.connect.enabled = true;
    services.dnsmasq.enable = true;
  };

  Config = let
    inherit (config.cluster) nodes region;
    deployType = config.currentCoreNode.deployType or config.currentAwsAutoScalingGroup.deployType;
    datacenter = config.currentCoreNode.datacenter or config.currentAwsAutoScalingGroup.datacenter;
    role = config.currentCoreNode.role or config.currentAwsAutoScalingGroup.role;
    primaryInterface = config.currentCoreNode.primaryInterface or config.currentAwsAutoScalingGroup.primaryInterface;

    cfg = config.services.consul;
    ownedChain = "/var/lib/consul/full.pem";
    ownedKey = "/var/lib/consul/cert-key.pem";
  in {
    # Consul firewall references:
    #   https://support.hashicorp.com/hc/en-us/articles/1500011608961-Checking-Consul-Network-Connectivity
    #   https://www.consul.io/docs/install/ports
    #
    # Consul ports common to both clients and servers
    networking.firewall.allowedTCPPorts = [
      8300  # server rpc
      8301  # lan serf
      8302  # wan serf
      8501  # https required for connect
      8502  # grpc required for connect
    ];
    networking.firewall.allowedUDPPorts = [
      8301  # lan serf
      8302  # wan serf
    ];

    services.consul = {
      addresses = { http = lib.mkDefault "127.0.0.1"; };

      clientAddr = "0.0.0.0";
      datacenter = if deployType == "aws" then region else datacenter;
      enableLocalScriptChecks = true;
      logLevel = "info";
      primaryDatacenter = if deployType == "aws" then region else datacenter;
      tlsMinVersion = "tls12";
      verifyIncoming = true;
      verifyIncomingRpc = true;
      verifyOutgoing = true;
      verifyServerHostname = true;

      caFile = pkiFiles.caCertFile;
      certFile = ownedChain;
      keyFile = ownedKey;

      telemetry = {
        dogstatsdAddr = "localhost:8125";
        disableHostname = true;
      };

      nodeMeta = {
        inherit nodeName;
        region = lib.mkIf (deployType != "prem") config.cluster.region;
      } // (lib.optionalAttrs ((config.currentCoreNode or null) != null) {
        inherit (config.currentCoreNode) domain;
        instanceType = lib.mkIf (deployType != "prem") config.currentCoreNode.instanceType;
      });

      # generate deterministic UUIDs for each node so they can rejoin.
      nodeId = lib.mkIf (config.currentCoreNode != null) (lib.fileContents
        (pkgs.runCommand "node-id" { buildInputs = [ pkgs.utillinux ]; }
          "uuidgen -s -n ab8c189c-e764-4103-a1a8-d355b7f2c814 -N ${nodeName} > $out"));

      bindAddr = ''{{ GetInterfaceIP "${primaryInterface}" }}'';

      advertiseAddr = ''{{ GetInterfaceIP "${primaryInterface}" }}'';

      # Allow cname local hostname lookups through consul via dnsmasq recursor
      recursors = [ ''{{ GetInterfaceIP "${primaryInterface}" }}'' ];

      retryJoin = (lib.mapAttrsToList (_: v: v.privateIP)
        (lib.filterAttrs (k: v: lib.elem k cfg.serverNodeNames) nodes))
        ++ lib.optionals (deployType == "aws")
        [ "provider=aws region=${region} tag_key=Consul tag_value=server" ];

      connect = {
        caProvider = "consul";
      };

      ports = {
        grpc = 8502;
        https = 8501;
        http = 8500;
      };
    };

    services.dnsmasq = {
      extraConfig = let
        inherit (config.services.vault) serverNodeNames;

        mkResolver = type: dnsPattern: port: lib.concatStringsSep "\n"
          (lib.mapAttrsToList (name: instance: "${type}=/${dnsPattern}/${instance.privateIP}${port}")
          (lib.filterAttrs (k: v: lib.elem k serverNodeNames) nodes));

        consulCoreDns = mkResolver "address" "core.vault.service.consul" "";
        consulDns = mkResolver "server" "consul" "#8600";
        consulDnsLocal = "server=/consul/127.0.0.1#8600";
      in ''
        # Ensure docker0 is also bound on client machines when it may not exist during dnsmasq startup:
        # - This ensures nomad docker driver jobs have dnsmasq access
        # - This enables nomad exec driver bridge mode jobs to use the docker bridge for dnsmasq access
        #   when explicitly defined as a nomad network dns server ip
        bind-dynamic

        # Declare core.vault.service.consul machines specifically in dnsmasq rather than hosts
        # to provide some minimal load balancing capability.  Certs config will typically include the
        # core.vault.service.consul defn for cores by default.
        ${consulCoreDns}

        # Redirect consul and deployType specific queries to their respective DNS servers.
        ${if role == "router" then ''
          # Routing machines require consul dns resolution upstream rather than localhost due to token config.
          ${consulDns}'' else consulDnsLocal}
        ${lib.optionalString (deployType != "prem") ''
          server=/internal/169.254.169.253#53''
        }

        # Configure reverse in-addr.arpa DNS lookups to consul
        ${lib.optionalString (deployType != "prem") ''
          rev-server=10.0.0.0/8,127.0.0.1#8600
          rev-server=172.16.0.0/16,127.0.0.1#8600''
        }

        # Define upstream DNS servers
        ${lib.optionalString (deployType != "prem") ''
          server=169.254.169.253''
        }
        server=8.8.8.8

        # Set cache and security
        cache-size=65536
        local-service

        # Append additional extraConfig from the ops repo as needed
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

in Imports // lib.mkMerge [
  Switches
  Config
]
