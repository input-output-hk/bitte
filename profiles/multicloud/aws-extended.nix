{lib, ...}: let
  Imports = {imports = [];};

  Switches = {};

  Config = let
    awsExtCredsAttrs = {
      AWS_CONFIG_FILE = "/etc/aws/config";
      AWS_SHARED_CREDENTIALS_FILE = "/etc/aws/credentials";
    };
  in {
    # Get misc systemd services working in an awsExt environment.
    systemd.services = {
      consul.environment = awsExtCredsAttrs;
      vault-agent.environment = awsExtCredsAttrs;
      promtail.environment = awsExtCredsAttrs;
    };
  };
in
  Imports
  // lib.mkMerge [
    Switches
    Config
  ]
