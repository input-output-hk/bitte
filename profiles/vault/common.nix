{ config, lib, pkgs, ... }: let

  Imports = { imports = [ ]; };

  Switches = {
    services.vault-agent.enable = true;
  };

  Config = {
    services.vault-agent = {
      autoAuthMethod = "aws";

      autoAuthConfig = {
        type = "iam";
        role = "${config.cluster.name}-${config.services.vault-agent.role}";
        header_value = config.cluster.domain;
      };

    };
  };

in Imports // lib.mkMerge [
  Switches
  Config
]
