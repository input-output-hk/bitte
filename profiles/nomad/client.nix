{ pkgs, ... }: {
  imports = [ ./default.nix ];

  services.nomad = {
    enable = true;
    client.enabled = true;

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
}
