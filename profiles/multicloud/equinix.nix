{
  config,
  lib,
  pkgs,
  nodeName,
  pkiFiles,
  ...
}: let
  Imports = {imports = [];};

  Switches = {
    # Required due to Equinix networkd default and wireless dhcp default
    networking.useDHCP = false;
  };

  Config = {
    services.consul = {
      # Equinix has both public and private IP bound to the bond0 primary interface and consul
      # will otherwise choose the public interface to adverstise on without this modification.
      # The 10.0.0.0/8 network selector should be generic enough for all default equinix machine
      # private IP assignments.
      advertiseAddr = lib.mkForce ''{{ GetPrivateInterfaces | include "network" "10.0.0.0/8" | attr "address" }}'';
      bindAddr = lib.mkForce ''{{ GetPrivateInterfaces | include "network" "10.0.0.0/8" | attr "address" }}'';
    };

    services.nomad.name = lib.mkForce config.currentCoreNode.name;

    networking.firewall = {
      # Equinix machines typically have only two physically connected NICs which are bonded for throughput and HA.
      # Both public and private IP get assigned to bond0 and therefore we can't open ports to only the private IP interface
      # without also opening to the public interface using the pre-canned firewall nixos options.  So, we'll clear
      # the standard client port openings (other than ssh) and re-declare them open for only the private IP.
      allowedTCPPorts = lib.mkForce [22];
      allowedTCPPortRanges = lib.mkForce [];
      allowedUDPPorts = lib.mkForce [];
      extraCommands = ''
        # Accept connections to the allowed TCP ports at the private IP.
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 4646 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 4647 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8300 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8301 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8302 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8501 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 8502 -j nixos-fw-accept

        # Accept connections to the allowed TCP port ranges at the private IP.
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 22000:32000 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 21000:21255 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p tcp --dport 21500:21755 -j nixos-fw-accept

        # Accept packets on the allowed UDP ports at the private IP.
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p udp --dport 8301 -j nixos-fw-accept
        iptables -A nixos-fw -d ${config.currentCoreNode.privateIP}/32 -p udp --dport 8302 -j nixos-fw-accept
      '';
    };
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
