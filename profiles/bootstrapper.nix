{ config, ... }:
let inherit (config.cluster) domain;
in {
  imports = [ ./bootstrap.nix ./acme.nix ];

  services = {
    haproxy = {
      enable = false;
      services = {
        count-dashboard = {
          host = "countdash.${domain}";
          count = 1;
        };

        consul = {
          host = "consul.${domain}";
          count = 3;
          ssl = true;
          # crt = "/run/keys/cert-key.pem";
        };

        vault = {
          host = "vault.${domain}";
          count = 3;
          check-ssl = true;
          ssl = true;
        };

        nomad = {
          host = "nomad.${domain}";
          count = 3;
          check-ssl = true;
          ssl = true;
        };
      };
    };

    nginx.enable = true;
    vault-acl.enable = true;
    consul-policies.enable = true;
  };
}
