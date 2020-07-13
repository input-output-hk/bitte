{ lib, config, ... }:

let
  inherit (builtins) mapAttrs;
  inherit (lib) mapAttrsToList concatStringsSep mkOption optionalString;
  inherit (lib.types) submodule str attrsOf ints enum bool nullOr;

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
      "/etc/ssl/certs/fullchain.pem"
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
        } _${name}._tcp.service.consul ${haProxyOptions name value}
  '');
in {
  options = {
    services.haproxy.services = mkOption {
      type = attrsOf (submodule {
        options = {
          host = mkOption { type = str; };

          verify = mkOption {
            type = enum [ "none" "required" ];
            default = "none";
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
      default = { };
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
          bind *:80
          timeout connect 5000
          timeout check 5000
          timeout client 30000
          timeout server 30000
          ${acl}
          ${useBackends}

        ${backends}
      '';
    };
  };
}
