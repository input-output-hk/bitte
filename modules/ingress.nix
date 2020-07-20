{ pkgs, config, lib, ... }:
let
  inherit (lib) mkIf mkEnableOption makeBinPath concatStringsSep mapAttrsToList;
  inherit (config.cluster) domain;

  ingressConfig = pkgs.writeText "ingress.hcl" ''
    Kind = "ingress-gateway"
    Name = "eu-central-1-ingress"

    TLS {
      Enabled = true
    }

    Listeners = [
      {
        Port = 8080
        Protocol = "http"
        Services = [
          {
            Name = "web"
            Hosts = [
              "web.testnet.atalaprism.io",
              "web.ingress.consul:8080"
            ]
          },
          {
            Name = "landing"
            Hosts = [
              "landing.testnet.atalaprism.io",
              "landing.ingress.consul:8080"
            ]
          },
          {
            Name = "connector"
            Hosts = [
              "connector.testnet.atalaprism.io",
              "connector.ingress.consul:8080"
            ]
          },
          {
            Name = "nomad"
          },
          {
            Name = "vault"
          }
        ]
      }
    ]
  '';

  haproxyService = pkgs.toPrettyJSON "haproxy-service" {
    service = {
      name = "haproxy";
      port = 443;
    };
  };

  caTmpl = pkgs.writeText "ca.crt.tmpl" ''
    {{range caRoots}}{{.RootCertPEM}}{{end}}
  '';

  certsTmpl = pkgs.writeText "certs.pem.tmpl" ''
    {{with caLeaf "haproxy"}}{{.PrivateKeyPEM}}{{.CertPEM}}{{end}}
  '';

  haproxyIngress = pkgs.toPrettyJSON "haproxy.json" {
    exec = [{ command = "${pkgs.haproxy}/bin/haproxy -f haproxy.conf"; }];
    template = [
      {
        source = caTmpl;
        destination = "ca.crt";
      }
      {
        source = certsTmpl;
        destination = "certs.pem";
      }
      {
        source = haproxyTemplate;
        destination = "haproxy.conf";
      }
    ];
  };

  corsHeaders = concatStringsSep " "
    (mapAttrsToList (name: value: ''hdr ${name} "${value}"'') {
      access-control-allow-headers =
        "keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,custom-header-1,x-accept-content-transfer-encoding,x-accept-response-streaming,x-user-agent,x-grpc-web,grpc-timeout,userid,userId,requestNonce,did,didKeyId,didSignature";
      access-control-allow-methods = "GET, PUT, DELETE, POST, OPTIONS";
      access-control-allow-origin = "*";
      access-control-expose-headers = "grpc-status,grpc-message,userid,userId";
      access-control-max-age = "1728000";
    });

  haproxyTemplate = pkgs.writeText "haproxy.conf.tmpl" ''
    global
      log /dev/log local0 info
      stats socket /run/ingress/haproxy.sock mode 600 expose-fd listeners level user

    defaults
      log global
      mode http
      option httplog
      option dontlognull
      timeout connect 5000
      timeout client 50000
      timeout server 50000
      default-server init-addr none
      balance roundrobin

    resolvers consul
      nameserver dnsmasq 127.0.0.1:53
      accepted_payload_size 8192
      hold valid 5s

    backend web
      default-server ssl verify required ca-file ca.crt crt certs.pem check check-ssl maxconn 200000
    {{ range connect "web" }}
      server {{.ID}} {{.Address}}:{{.Port}}
    {{- end }}

    backend connector
      http-request return status 200 ${corsHeaders} if { method OPTIONS }
      http-after-response set-header access-control-allow-headers "keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,custom-header-1,x-accept-content-transfer-encoding,x-accept-response-streaming,x-user-agent,x-grpc-web,grpc-timeout,userid,userId,requestNonce,did,didKeyId,didSignature"
      http-after-response set-header access-control-allow-methods "GET, PUT, DELETE, POST, OPTIONS"
      http-after-response set-header access-control-allow-origin "*"
      http-after-response set-header access-control-expose-headers "grpc-status,grpc-message,userid,userId"
      http-after-response set-header access-control-max-age "1728000"
      timeout connect 5000000
      timeout server 5000000
      default-server ssl verify required ca-file ca.crt crt certs.pem maxconn 200000 alpn h2
    {{ range connect "connector" }}
      server {{.ID}} {{.Address}}:{{.Port}}
    {{- end }}

    backend landing
      default-server ssl verify required ca-file ca.crt crt certs.pem check check-ssl maxconn 200000
    {{ range connect "landing" }}
      server {{.ID}} {{.Address}}:{{.Port}}
    {{- end }}

    backend nomad
      default-server ssl verify required ca-file consul-ca.pem crt consul-crt.pem check check-ssl maxconn 2000 
    {{ range service "http.nomad" }}
      server {{.ID}} {{.Address}}:{{.Port}}
    {{- end }}

    backend vault
      default-server ssl verify required ca-file consul-ca.pem crt consul-crt.pem check check-ssl maxconn 2000 resolve-opts allow-dup-ip resolve-prefer ipv4 resolvers consul
      server-template vault 3 _vault._tcp.service.consul

    backend consul
      default-server check maxconn 2000
    option httpchk HEAD /
    {{ range $key, $value := service "consul" }}
      server consul{{ $key }} {{.Address}}:8500
    {{- end }}

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

    frontend grpc
      bind *:4422 ssl crt acme-full.pem alpn h2
      timeout client 5000000
      default_backend connector

    frontend app
      bind *:443 ssl crt acme-full.pem alpn h2,http/1.1

      acl host_landing hdr(host) -i landing.${domain}
      use_backend landing if host_landing

      acl host_web hdr(host) -i web.${domain}
      use_backend web if host_web

      acl host_nomad hdr(host) -i nomad.${domain}
      use_backend nomad if host_nomad

      acl host_vault hdr(host) -i vault.${domain}
      use_backend vault if host_vault

      acl host_consul hdr(host) -i consul.${domain}
      use_backend consul if host_consul

      default_backend landing
  '';

in {
  options = {
    services.ingress.enable = mkEnableOption "Enable Envoy ingress";
  };

  config = mkIf config.services.ingress.enable {
    systemd.services.ingress = {
      wantedBy = [ "multi-user.target" ];
      after = [ "consul.service" ];

      serviceConfig = let
        stopPost = pkgs.writeShellScriptBin "ingress-stop-post" ''
          set -euo pipefail

          PATH="${lib.makeBinPath (with pkgs; [ consul vault-bin glibc gawk ])}"

          VAULT_TOKEN="$(vault login -method aws -no-store -token-only)"
          export VAULT_TOKEN
          CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/consul-server-default)"
          export CONSUL_HTTP_TOKEN

          set -x

          consul services deregister ${haproxyService}
        '';

        preScript = pkgs.writeShellScriptBin "ingress-start-pre" ''
          export PATH="${makeBinPath [ pkgs.coreutils ]}"
          set -exuo pipefail
          cp /etc/ssl/certs/cert-key.pem consul-key.pem
          cp /etc/ssl/certs/full.pem consul-ca.pem
          cat consul-ca.pem consul-key.pem > consul-crt.pem

          cp /var/lib/acme/${domain}/full.pem acme-full.pem
          cp /var/lib/acme/${domain}/chain.pem acme-chain.pem
          chown --reference . --recursive .
        '';
      in {
        StateDirectory = "ingress";
        RuntimeDirectory = "ingress";
        WorkingDirectory = "/var/lib/ingress";
        DynamicUser = true;
        User = "ingress";
        Group = "ingress";
        ProtectSystem = "full";
        TimeoutStopSec = "30s";
        RestartSec = "10s";
        Restart = "on-failure";
        StartLimitInterval = "20s";
        StartLimitBurst = 10;
        ExecStartPre = "!${preScript}/bin/ingress-start-pre";
        ExecStopPost = "${stopPost}/bin/ingress-stop-post";
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      };

      path = with pkgs; [ consul consul-template vault-bin gawk glibc ];

      environment = {
        CONSUL_CACERT = "/etc/ssl/certs/full.pem";
        CONSUL_CLIENT_CERT = "/etc/ssl/certs/cert.pem";
        CONSUL_CLIENT_KEY = "consul-key.pem";
        CONSUL_HTTP_ADDR = "https://127.0.0.1:8501";
        CONSUL_HTTP_SSL = "true";
      };

      script = ''
        set -euo pipefail

        VAULT_TOKEN="$(vault login -method aws -no-store -token-only)"
        export VAULT_TOKEN
        CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/consul-server-default)"
        export CONSUL_HTTP_TOKEN

        set -x

        consul services register ${haproxyService}

        exec consul-template -config ${haproxyIngress}
      '';
    };
  };
}
