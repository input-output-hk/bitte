{ config, lib, ... }:
let
  inherit (builtins) attrNames;
  inherit (lib) listToAttrs imap1 nameValuePair;
  inherit (config) cluster;
  inherit (cluster) instances domain;

  default-server = {
    ca-file = "/etc/ssl/certs/full.pem";
    check = true;
    check-ssl = true;
    maxconn = 20;
    resolve-opts = [ "allow-dup-ip" ];
    resolve-prefer = "ipv4";
    resolvers = [ "consul" ];
    ssl = true;
    verify = "none";
  };
in {
  imports = [ ./bootstrap.nix ./acme.nix ];

  services = {
    s3-upload.enable = true;
    nginx.enable = false;
    consul-policies.enable = true;
    nomad-acl.enable = true;
    vault-acl.enable = true;
    haproxy = {
      enable = false;

      resolvers = {
        consul = {
          nameserver = "dnsmasq 127.0.0.1:53";
          accepted_payload_size = 8192;
          hold = "valid 5s";
        };
      };

      frontend = {
        stats = {
          bind = "*:1936";
          extraConfig = ''
            stats uri /
            stats show-legends
            no log
          '';
        };
        # connector_cluster/connector2 0/0/3/7/10 503 233 - - ---- 3/3/0/0/0 0/0
        # "OPTIONS https://connector.testnet.atalaprism.io/io.iohk.prism.intdemo.protos.IDService/GetConnectionToken HTTP/2.0"
        # ingress-http = {
        #   bind = "*:443 ssl crt /var/lib/acme/${domain}/full.pem alpn h2,http/1.1";
        #   extraConfig = ''
        #     redirect scheme https if !{ ssl_fc }

        #     acl host_consul hdr(host) -i consul.${domain}
        #     acl host_vault hdr(host) -i vault.${domain}
        #     acl host_nomad hdr(host) -i nomad.${domain}
        #     acl host_web hdr(host) -i web.${domain}
        #     acl host_landing hdr(host) -i landing.${domain}

        #     use_backend consul_cluster if host_consul
        #     use_backend vault_cluster if host_vault
        #     use_backend nomad_cluster if host_nomad
        #     use_backend web_cluster if host_web
        #     use_backend landing_cluster if host_landing
        #   '';
        # };

        ingress-grpc = {
          bind = "*:443 crt /var/lib/acme/${domain}/full.pem ssl alpn h2";
          extraConfig = ''
            acl host_connector hdr(host) -i connector.${domain}

            use_backend connector_cluster if host_connector
          '';
        };
      };

      backend = {
        consul_cluster = {
          default-server = {
            check = true;
            maxconn = 20;
          };

          server = listToAttrs (imap1 (idx: name:
            let instance = instances.${name};
            in nameValuePair "consul${toString idx}" {
              fqdn = "${instance.privateIP}:8500";
            }) (attrNames instances));

          extraConfig = ''
            option httpchk HEAD /
          '';
        };

        web_cluster = {
          inherit default-server;

          server-template = {
            prefix = "web";
            count = 2;
            fqdn = "web.ingress.consul:8080";
          };
        };

        connector_cluster = {
          default-server = default-server // { alpn = "h2"; };

          server-template = {
            prefix = "connector";
            count = 2;
            fqdn = "connector.ingress.consul:8080";
          };
        };

        landing_cluster = {
          inherit default-server;

          server-template = {
            prefix = "landing";
            count = 2;
            fqdn = "landing.ingress.consul:8080";
          };
        };

        nomad_cluster = {
          inherit default-server;

          server-template = {
            prefix = "nomad";
            count = 3;
            fqdn = "_nomad._http.service.consul";
          };
        };

        vault_cluster = {
          inherit default-server;

          server-template = {
            prefix = "vault";
            count = 3;
            fqdn = "_vault._tcp.service.consul";
          };
        };
      };
    };
  };
}
