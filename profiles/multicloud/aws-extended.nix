{
  config,
  lib,
  pkgs,
  nodeName,
  pkiFiles,
  ...
}: let
  Imports = {imports = [];};

  Switches = {};

  Config = let
    awsExtCredsAttrs = {
      AWS_CONFIG_FILE = "/etc/aws/config";
      AWS_SHARED_CREDENTIALS_FILE = "/etc/aws/credentials";
    };

    awsExtCredsShell = ''
      export AWS_CONFIG_FILE="/etc/aws/config"
      export AWS_SHARED_CREDENTIALS_FILE="/etc/aws/credentials"
    '';
  in {
    # Get sops working in systemd awsExt
    secrets.install = {
      certs.preScript = awsExtCredsShell;
      consul-server.preScript = awsExtCredsShell;
      github.preScript = awsExtCredsShell;
      nomad-server.preScript = awsExtCredsShell;
    };

    # Get vault-agent working in systemd awsExt
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
