{ config, lib, ... }: {
  tf.consul.configuration = {
    terraform.backend.remote = {
      organization = "iohk-midnight";
      workspaces = [{ prefix = "${config.cluster.name}_"; }];
    };

    provider.consul = {
      address = "https://consul.${config.cluster.domain}";
      datacenter = "eu-central-1";
    };

    resource.consul_intention = lib.listToAttrs
      (lib.forEach config.services.consul.intentions (intention:
        lib.nameValuePair
        "${intention.sourceName}_${intention.destinationName}" {
          source_name = intention.sourceName;
          destination_name = intention.destinationName;
          action = intention.action;
        }));
  };
}
