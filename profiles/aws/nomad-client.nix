{ config, ... }: { services.nomad.datacenter = config.asg.region; }
