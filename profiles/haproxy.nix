{ lib, config, ... }:

let
  inherit (builtins) mapAttrs;
  inherit (lib) mapAttrsToList concatStringsSep mkOption optionalString;
  inherit (lib.types) submodule str attrsOf ints enum bool nullOr;
  inherit (config.cluster) domain;

  mapServices = sep: f:
    concatStringsSep sep (mapAttrsToList f config.services.haproxy.services);

  acl = mapServices "  " (name: value: ''
    acl host_${name} hdr(host) -i ${value.host}
  '');

  useBackends = mapServices "  " (name: value: ''
    use_backend ${name}_cluster if host_${name}
  '');

  haProxyOptions = name: options:
    concatStringsSep " " [
      "resolvers"
      "consul"
      "resolve-opts"
      "allow-dup-ip"
      "resolve-prefer"
      "ipv4"
      "check"
      (optionalString options.check-ssl "check-ssl")
      (optionalString options.ssl "ssl")
      "verify"
      options.verify
      "ca-file"
      "/etc/ssl/certs/full.pem"
      (optionalString (options.crt != null) "crt ${options.crt}")
    ];

  backends = mapServices "\n" (name: value: ''
    backend ${name}_cluster
        balance leastconn
        timeout connect 5000
        timeout check 5000
        timeout client 30000
        timeout server 30000
        server-template ${name} ${
          toString value.count
        } _${name}._${value.port}.service.consul ${haProxyOptions name value}
  '');
in {
  options = {
    services.haproxy.services = mkOption {
      default = { };
      type = attrsOf (submodule {
        options = {
          host = mkOption { type = str; };

          verify = mkOption {
            type = enum [ "none" "required" ];
            default = "none";
          };

          port = mkOption {
            type = str;
            default = "tcp";
          };

          count = mkOption {
            type = ints.positive;
            default = 1;
          };

          ssl = mkOption {
            type = bool;
            default = false;
          };

          check-ssl = mkOption {
            type = bool;
            default = false;
          };

          crt = mkOption {
            type = nullOr str;
            default = null;
          };
        };
      });
    };
  };

  config = {
    services.haproxy = {
      config = ''
        global
          log /dev/log local0 info

        defaults
          log global
          mode http
          option httplog
          option dontlognull
          option forwardfor
          option http-server-close

        resolvers consul
          nameserver dnsmasq 127.0.0.1:53
          accepted_payload_size 8192
          hold valid 5s

        frontend stats
          bind *:1936
          stats uri /
          stats show-legends
          no log
          timeout connect 5000
          timeout check 5000
          timeout client 30000
          timeout server 30000

        frontend ingress
          bind *:443 ssl crt /var/lib/acme/${domain}/full.pem
          redirect scheme https if !{ ssl_fc }
          timeout connect 5000
          timeout check 5000
          timeout client 30000
          timeout server 30000
          ${acl}
          acl host_consul hdr(host) -i consul.${domain}
          ${useBackends}
          use_backend consul_cluster if host_consul

        backend consul_cluster
            balance leastconn
            timeout connect 5000
            timeout check 5000
            timeout client 30000
            timeout server 30000
            balance roundrobin
            option httpchk HEAD /
            default-server check maxconn 20
            server consul1 10.0.0.10:8500
            server consul2 10.0.32.10:8500
            server consul3 10.0.64.10:8500

        ${backends}
      '';
    };
  };
}
