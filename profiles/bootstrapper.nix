{ config, ... }:
let inherit (config.cluster) domain;
in {
  imports = [ ./bootstrap.nix ./acme.nix ];

  services = {
    haproxy = {
      enable = true;
      services = {
        web = {
          host = "countdash.${domain}";
          port = "tcp";
          count = 1;
          # check-ssl = true;
          # ssl = true;
        };

        # TODO: this is atm hardcoded in haproxy config because it behaves differently from all the others.
        # consul = {
        #   host = "consul.${domain}";
        #   count = 3;
        #   port = "https";
        #   check-ssl = true;
        #   ssl = true;
        # };

        vault = {
          host = "vault.${domain}";
          count = 3;
          port = "tcp";
          check-ssl = true;
          ssl = true;
        };

        nomad = {
          host = "nomad.${domain}";
          count = 3;
          port = "http";
          check-ssl = true;
          ssl = true;
        };
      };
    };

    nginx.enable = false;
    consul-policies.enable = true;
    nomad-acl.enable = true;
    vault-acl.enable = true;
  };
}