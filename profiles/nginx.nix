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
    security.acme.certs."ipxe.${config.cluster.domain}".keyType = "rsa4096";

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

    systemd.tmpfiles.rules = let flakeBall = pkgs.runCommand "flake.tar.xz" {} ''
      tar cJf $out -C ${self.outPath}/ .
    '';
    in [
      "d /var/lib/nginx/nixos-images 0755 nginx nginx -"
      "Z /var/lib/nginx 0755 nginx nginx -"
      "L+ /var/lib/nginx/nixos-images/source - - - - ${self.outPath}"
      "L+ /var/lib/nginx/nixos-images/source.tar.xz - - - - ${flakeBall}"
    ];

    systemd.services.image-builder = {
      after = [ "vault-agent.service" "network-online.target" ];
      requires = [ "vault-agent.service" ];
      wantedBy = [ "nginx.service" "multi-user.target" ];

      serviceConfig = {
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
        StateDirectory = "image-builder";
        Type = "oneshot";
        WorkingDirectory = "/var/lib/image-builder";
      };

      environment = {
        inherit (config.environment.variables)
          AWS_DEFAULT_REGION VAULT_CACERT VAULT_ADDR VAULT_FORMAT;
      };

      path = with pkgs; [
        vault-bin glibc gawk gnugrep coreutils nixFlakes
      ];

      script = ''
        set -euo pipefail

        set +x
        VAULT_TOKEN="$(< /run/keys/vault-token)"
        export VAULT_TOKEN
        set -x

        export HOME="$PWD"

        if ! grep github.com "$HOME/.ssh/known_hosts"; then
          mkdir -p "$HOME/.ssh"

          echo 'github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==' \
          >> "$HOME/.ssh/known_hosts"
        fi

        if [ -s "$HOME/.ssh/id_rsa" ]; then
          vault kv get secret/github-deploy-key > "$HOME/.ssh/id_rsa"
          chmod 0600 "$HOME/.ssh/id_rsa"
        fi

        for name in ${toString (attrNames config.cluster.autoscalingGroups)}; do
          flakeAttr="clusters.${config.cluster.name}.groups-ipxe.$name-ipxe.config.system.build.ipxeBootDir"
          flake="${self.outPath}"

          nix build "$flake#$flakeAttr" -o "/var/lib/nginx/nixos-images/$name"
        done
      '';
    };
  };
}
