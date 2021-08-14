{ lib, nodeName, config, ... }: {
  imports = [ ../consul ];

  services.consul = {
    datacenter = "dc1";
    primaryDatacenter = "dc1";
    nodeMeta = { inherit nodeName; };

    bindAddr = ''{{ GetInterfaceIP "eth0" }}'';
    advertiseAddr = ''{{ GetInterfaceIP "eth0" }}'';

    retryJoin =
      (lib.mapAttrsToList (_: v: v.privateIP) config.cluster.instances);
  };
}
