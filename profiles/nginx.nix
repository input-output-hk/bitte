{ self, lib, pkgs, config, nodeName, ... }:
let
  cfg = config.services.nginx;
  inherit (lib) mkIf mkDefault;
  inherit (builtins) attrNames;
in {
  config = mkIf cfg.enable {
    networking.firewall = { allowedTCPPorts = [ 80 443 ]; };

    # TODO: distribute this across core nodes to remove the SPOF

    services.nginx = {
      # enableReload = true;

      appendHttpConfig = ''
        error_log syslog:server=unix:/dev/log;
        access_log syslog:server=unix:/dev/log combined;
      '';

      virtualHosts."consul.${config.cluster.domain}" = {
        useACMEHost = config.cluster.domain;
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:8500/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_read_timeout 310s;
            proxy_buffering off;
          '';
        };

        locations."/cluster-bootstrap/" = {
          extraConfig = ''
            alias /var/lib/nginx/nixos-images/;
            autoindex on;
          '';
        };
      };

      virtualHosts."nomad.${config.cluster.domain}" = {
        useACMEHost = config.cluster.domain;
        forceSSL = true;

        locations."/" = {
          proxyPass = "https://127.0.0.1:4646/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_ssl_trusted_certificate /etc/ssl/certs/full.pem;
            proxy_ssl_protocols TLSv1.3;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_read_timeout 310s;
            proxy_buffering off;
          '';
        };
      };

      virtualHosts."vault.${config.cluster.domain}" = {
        useACMEHost = config.cluster.domain;
        forceSSL = true;

        locations."/" = {
          proxyPass = "https://127.0.0.1:8200/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_ssl_trusted_certificate /etc/ssl/certs/full.pem;
            proxy_ssl_protocols TLSv1.3;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_read_timeout 310s;
            proxy_buffering off;
          '';
        };
      };

      virtualHosts."countdash.${config.cluster.domain}" = {
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://count-dashboard.service.consul:9002";
        };
      };
    };

    systemd.tmpfiles.rules = let
      flakeBall = pkgs.runCommand "flake.tar.xz" { } ''
        tar cJf $out -C ${self.outPath}/ .
      '';
    in [
      "d /var/lib/nginx/nixos-images 0755 nginx nginx -"
      "Z /var/lib/nginx 0755 nginx nginx -"
      "L+ /var/lib/nginx/nixos-images/source - - - - ${self.outPath}"
      "L+ /var/lib/nginx/nixos-images/source.tar.xz - - - - ${flakeBall}"
      "L+ /var/lib/nginx/nixos-images/client.enc.json - - - - /var/lib/nginx/client.enc.json"
      "L+ /var/lib/nginx/nixos-images/vault.enc.json - - - - /var/lib/nginx/vault.enc.json"
      "L+ /var/lib/nginx/nixos-images/ca.pem - - - - /etc/ssl/certs/ca.pem"
      "L+ /var/lib/nginx/nixos-images/full.pem - - - - /etc/ssl/certs/full.pem"
    ];
  };
}
