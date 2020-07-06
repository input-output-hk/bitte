let
  inherit (builtins) getFlake mapAttrs head attrNames;

  flake = getFlake (toString ./.);
  ncs = flake.nixosConfigurations;
  ncName = head (attrNames ncs);
  nc = ncs.${ncName};
  cluster = nc.config.cluster;

  mapASG = _: asg: {
    user_data_target = toString asg.userDataTarget;
    user_data_source = toString asg.userDataSource;
  };

  mapInstance = name: instance: { private_ip = instance.privateIP; };
in {
  inherit (cluster) region name;
  autoscaling_groups = mapAttrs mapASG cluster.autoscalingGroups;
  instances = mapAttrs mapInstance cluster.instances;
}
