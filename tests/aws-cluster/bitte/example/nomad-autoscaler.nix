{ self, config, lib, ... }:
let
  eachASG = lib.flip lib.mapAttrs config.cluster.autoscalingGroups;
in
{
  imports = [ ("${toString self}" + "/profiles/nomad/autoscaler.nix") ];

  services.nomad-autoscaler.policies = eachASG (name: asg: {
    min = 2;
    max = 4;

    policy.cooldown = lib.mkForce "5m";

    policy.check = {
      mem_allocated_percentage.strategy.target-value.target = 70.0;
      cpu_allocated_percentage.strategy.target-value.target = 70.0;
    };
  });
}
