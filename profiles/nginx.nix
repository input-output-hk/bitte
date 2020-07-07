{ self, lib, pkgs, config, nodeName, ... }:
let
  cfg = config.services.nginx;
  inherit (lib) mkIf mkDefault;
  inherit (builtins) attrNames;
in {
  config = mkIf cfg.enable {
    networking.firewall = { allowedTCPPorts = [ 80 443 ]; };

    security.acme.acceptTerms = lib.mkForce true;
    security.acme.email = lib.mkForce "michael.fellinger@iohk.io";
    # security.acme.certs."ipxe.${config.cluster.domain}".keyType = "rsa4096";

    # TODO: distribute this across core nodes to remove the SPOF

    services.nginx = {
      # enableReload = true;

      appendHttpConfig = ''
        error_log syslog:server=unix:/dev/log;
        access_log syslog:server=unix:/dev/log combined;
      '';

      virtualHosts."consul.${config.cluster.domain}" = {
        # enableACME = true;
        # forceSSL = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:8500/";
          proxyWebsockets = true;
        };
      };

      virtualHosts."nomad.${config.cluster.domain}" = {
        # enableACME = true;
        # forceSSL = true;

        locations."/" = {
          proxyPass = "https://127.0.0.1:4646/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_ssl_trusted_certificate /etc/ssl/certs/all.pem;
            proxy_ssl_protocols TLSv1.3;
          '';
        };
      };

      virtualHosts."vault.${config.cluster.domain}" = {
        # enableACME = true;
        # forceSSL = true;

        locations."/" = {
          proxyPass = "https://127.0.0.1:8200/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_ssl_trusted_certificate /etc/ssl/certs/all.pem;
            proxy_ssl_protocols TLSv1.3;
          '';
        };
      };

      # virtualHosts."countdash.${config.cluster.domain}" = {
      #   locations."/" = {
      #     proxyWebsockets = true;
      #     proxyPass = "http://count-dashboard.service.consul:9002";
      #   };
      # };

      # logError = "stderr debug";
      # recommendedTlsSettings = true;
      # sslProtocols = "TLSv1.2";
      # sslCiphers = "AES256-SHA256";

      virtualHosts."ipxe.${config.cluster.domain}" = {
        # enableACME = false;
        # forceSSL = false;
        # http2 = false;
        root = "/var/lib/nginx/nixos-images";
        locations."/" = {
          extraConfig = ''
            autoindex on;
          '';
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
      "L+ /var/lib/nginx/nixos-images/all.pem - - - - /etc/ssl/certs/all.pem"
    ];
  };
}
