{ pkgs, config, ... }: {
  imports = [ ./default.nix ];

  services.nomad = {
    enable = true;
    client.enabled = true;

    datacenter = config.asg.region;

    plugin.rawExec.enabled = true;
    plugin.docker.auth = {
      # helper = "ecr";
      # This configuration is ignored, we set tmpfiles in nomad module for now...
      config = (pkgs.toPrettyJSON "config" {
        credHelpers = {
          "895947072537.dkr.ecr.us-east-2.amazonaws.com" = "ecr-login";
        };
      }).outPath;
    };
  };

  environment.etc."docker-mounts/db/init.sql" = {
    mode = "0644";
    text = ''
      CREATE DATABASE connector;
      CREATE USER connector WITH ENCRYPTED PASSWORD 'connector';
      GRANT ALL PRIVILEGES ON DATABASE connector TO connector;

      CREATE DATABASE node;
      CREATE USER node WITH ENCRYPTED PASSWORD 'node';
      GRANT ALL PRIVILEGES ON DATABASE node TO node;

      CREATE DATABASE demo;
      CREATE USER demo WITH ENCRYPTED PASSWORD 'demo';
      GRANT ALL PRIVILEGES ON DATABASE demo TO demo;
    '';
  };
}
