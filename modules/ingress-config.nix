{ pkgs, config, lib, ... }:
let
  inherit (lib) mkIf makeBinPath concatStringsSep mapAttrsToList;
  inherit (config.cluster) domain instances;
  acme-full = "/etc/ssl/certs/${domain}-full.pem";
in {
  options = {
    services.ingress-config = {
      enable = lib.mkEnableOption "Enable Ingress configuration generation";

      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = ''
          {{- range services -}}
            {{- if .Tags | contains "ingress" -}}
              {{- range service .Name -}}
                {{- if .ServiceMeta.IngressServer }}

          backend {{ .ID }}
            mode {{ or .ServiceMeta.IngressMode "http" }}
            default-server resolve-prefer ipv4 resolvers consul resolve-opts allow-dup-ip
            {{ .ServiceMeta.IngressBackendExtra | trimSpace | indent 2 }}
            server {{.ID}} {{ .ServiceMeta.IngressServer }}

                  {{- if (and .ServiceMeta.IngressBind (ne .ServiceMeta.IngressBind "*:443") ) }}

          frontend {{ .ID }}
            bind {{ .ServiceMeta.IngressBind }}
            mode {{ or .ServiceMeta.IngressMode "http" }}
            {{ .ServiceMeta.IngressFrontendExtra | trimSpace | indent 2 }}
            default_backend {{ .ID }}
                  {{- end }}
                {{- end -}}
              {{- end -}}
            {{- end -}}
          {{- end }}
        '';
      };

      extraGlobalConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };

      extraHttpsFrontendConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };

      extraHttpsBackends = lib.mkOption {
        type = lib.types.lines;
        default = ''
          {{- range services -}}
            {{- if .Tags | contains "ingress" -}}
              {{- range service .Name -}}
                {{- if (and (eq .ServiceMeta.IngressBind "*:443") .ServiceMeta.IngressServer) }}
            use_backend {{ .ID }} if { hdr(host) -i {{ .ServiceMeta.IngressHost }} } {{ .ServiceMeta.IngressIf }}
                {{- end }}
              {{- end -}}
            {{- end -}}
          {{- end }}
        '';
      };

      extraHttpsAcls = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
    };
  };

  config = mkIf config.services.ingress-config.enable (let
    haproxyTemplate = pkgs.writeText "haproxy.conf.tmpl" ''
      global
        stats socket /run/ingress/haproxy.sock mode 600 expose-fd listeners level user
        log /dev/log local0 info
        lua-prepend-path ${pkgs.haproxy-auth-request}/usr/share/haproxy/?/http.lua
        lua-prepend-path ${pkgs.lua53Packages.dkjson}/share/lua/5.3/dk?.lua
        lua-load ${pkgs.haproxy-auth-request}/usr/share/haproxy/auth-request.lua
        lua-load ${pkgs.haproxy-cors}/usr/share/haproxy/haproxy-lua-cors/cors.lua
        ${config.services.ingress-config.extraGlobalConfig}

      defaults
        log global
        mode http
        option httplog
        option dontlognull
        timeout connect 5000
        timeout client 310000
        timeout server 310000
        default-server init-addr none
        balance roundrobin

      resolvers consul
        nameserver dnsmasq ${instances.core-1.privateIP}:53
        accepted_payload_size 8192
        hold valid 5s

      backend grafana
        default-server check maxconn 2000
        server grafana 127.0.0.1:3000

      backend oauth_proxy
        mode http
        server auth_request 127.0.0.1:4180 check

      backend nomad
        default-server ssl ca-file consul-ca.pem check check-ssl maxconn 2000
      {{ range service "http.nomad" }}
        server {{.ID}} {{.Address}}:{{.Port}}
      {{- end }}

      backend vault
        default-server ssl ca-file consul-ca.pem check check-ssl maxconn 2000 resolve-opts allow-dup-ip resolve-prefer ipv4 resolvers consul
      {{ range service "active.vault" }}
        server {{.ID}} {{.Address}}:{{.Port}}
      {{- end }}

      backend consul
        default-server check maxconn 2000
        option httpchk HEAD /
        server consul 127.0.0.1:8500

      backend docker
        mode http
        http-request set-header X-Forwarded-Proto "https"
        server docker 127.0.0.1:5000

      frontend stats
        bind *:1936
        stats uri /
        stats show-legends
        stats refresh 30s
        stats show-node
        no log

      frontend http
        bind *:80
        acl http ssl_fc,not
        http-request redirect scheme https if http

      frontend https
        bind *:443 ssl crt ${acme-full} alpn h2,http/1.1

        acl oauth_proxy path_beg /oauth2/
        acl authenticated var(txn.auth_response_successful) -m bool
        acl is_monitoring hdr(host) -i monitoring.${domain}
        acl is_vault     hdr(host) -i vault.${domain}
        acl is_nomad     hdr(host) -i nomad.${domain}
        acl is_consul    hdr(host) -i consul.${domain}
        acl is_docker    hdr(host) -i docker.${domain}
        acl is_ui path_beg /ui
        ${config.services.ingress-config.extraHttpsAcls}

        http-request lua.auth-request oauth_proxy /oauth2/auth
        http-request add-header X-Authenticated-User %[var(req.auth_response_header.x_auth_request_email)]

        ${config.services.ingress-config.extraHttpsFrontendConfig}

        use_backend oauth_proxy if oauth_proxy
        use_backend docker if is_docker
        use_backend consul  if is_consul is_ui authenticated OR is_consul ! is_ui
        use_backend vault   if is_vault  is_ui authenticated OR is_vault ! is_ui
        use_backend nomad   if is_nomad  is_ui authenticated OR is_nomad ! is_ui
        ${config.services.ingress-config.extraHttpsBackends}

        use_backend oauth_proxy if is_ui ! authenticated OR is_monitoring ! authenticated
        use_backend grafana if is_monitoring

      ${config.services.ingress-config.extraConfig}
    '';

    haproxyConfig = pkgs.toPrettyJSON "haproxy" {
      template = [{
        source = haproxyTemplate;
        destination = "/var/lib/ingress/haproxy.conf";
        command = "${pkgs.systemd}/bin/systemctl reload ingress.service";
      }];
    };
  in {
    systemd.services.ingress-config = {
      wantedBy = [ "multi-user.target" ];
      after = [ "consul.service" ];

      serviceConfig = {
        TimeoutStopSec = "30s";
        RestartSec = "10s";
        Restart = "on-failure";
      };

      unitConfig = {
        StartLimitInterval = "20s";
        StartLimitBurst = 10;
      };

      path = with pkgs; [ consul consul-template vault-bin ];

      environment = {
        CONSUL_HTTP_ADDR = "http://127.0.0.1:8500";
        VAULT_ADDR = "http://127.0.0.1:8200";
        VAULT_CACERT = "/etc/ssl/certs/full.pem";
      };

      script = ''
        set -euo pipefail

        export VAULT_TOKEN="$(< /run/keys/vault-token)"
        CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/ingress)"
        export CONSUL_HTTP_TOKEN

        set -x

        exec consul-template -log-level debug -config ${haproxyConfig}
      '';
    };
  });
}
