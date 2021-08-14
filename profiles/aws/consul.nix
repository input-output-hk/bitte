{ lib, config, nodeName, ... }:
let inherit (config.cluster) instances region;
in {
  services.consul = {
    datacenter = region;
    primaryDatacenter = region;

    bindAddr = ''{{ GetInterfaceIP "ens5" }}'';
    advertiseAddr = ''{{ GetInterfaceIP "ens5" }}'';

    nodeMeta = {
      inherit region;
      inherit nodeName;
    } // (lib.optionalAttrs ((instances.${nodeName} or null) != null) {
      inherit (instances.${nodeName}) instanceType domain;
    });

    retryJoin = (lib.mapAttrsToList (_: v: v.privateIP) instances)
      ++ [ "provider=aws region=${region} tag_key=Consul tag_value=server" ];
  };
}
