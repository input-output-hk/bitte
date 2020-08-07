{ pkgs, config, lib, ... }:
let
  inherit (lib) mkIf mkEnableOption makeBinPath concatStringsSep mapAttrsToList;
  inherit (config.cluster) domain;

  caTmpl = pkgs.writeText "ca.crt.tmpl" ''
    {{range caRoots}}{{.RootCertPEM}}{{end}}
  '';

  certsTmpl = pkgs.writeText "certs.pem.tmpl" ''
    {{with caLeaf "haproxy"}}{{.PrivateKeyPEM}}{{.CertPEM}}{{end}}
  '';

  haproxyIngress = pkgs.toPrettyJSON "haproxy" {
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

  cors = {
    access-control-allow-headers =
      "keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,custom-header-1,x-accept-content-transfer-encoding,x-accept-response-streaming,x-user-agent,x-grpc-web,grpc-timeout,userid,userId,requestNonce,did,didKeyId,didSignature";
    access-control-allow-methods = "GET, PUT, DELETE, POST, OPTIONS";
    access-control-allow-origin = "*";
    access-control-expose-headers = "grpc-status,grpc-message,userid,userId";
    access-control-max-age = "1728000";
  };

  corsHeaders = concatStringsSep " "
    (mapAttrsToList (name: value: ''hdr ${name} "${value}"'') cors);

  corsSetHeaders = concatStringsSep "\n" (mapAttrsToList
    (name: value: ''http-after-response set-header ${name} "${value}"'') cors);

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

    backend nomad
      default-server ssl ca-file consul-ca.pem crt consul-crt.pem check check-ssl maxconn 2000 
    {{ range service "http.nomad" }}
      server {{.ID}} {{.Address}}:{{.Port}}
    {{- end }}

    backend vault
      default-server ssl ca-file consul-ca.pem crt consul-crt.pem check check-ssl maxconn 2000 resolve-opts allow-dup-ip resolve-prefer ipv4 resolvers consul
    {{ range service "active.vault" }}
      server {{.ID}} {{.Address}}:{{.Port}}
    {{- end }}

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

    frontend app
      bind *:443 ssl crt acme-full.pem alpn h2,http/1.1

      acl host_nomad hdr(host) -i nomad.${domain}
      use_backend nomad if host_nomad

      acl host_vault hdr(host) -i vault.${domain}
      use_backend vault if host_vault

      acl host_consul hdr(host) -i consul.${domain}
      use_backend consul if host_consul
  '';

in {
  options = {
    services.ingress.enable = mkEnableOption "Enable Envoy ingress";
  };

  config = mkIf config.services.ingress.enable {
    systemd.services.register-ingress = (pkgs.consulRegister {
      service = {
        name = "ingress";
        port = 443;
      };
    }).systemdService;

    systemd.services.ingress = {
      wantedBy = [ "multi-user.target" ];
      after = [ "consul.service" ];

      serviceConfig = let
        preScript = pkgs.writeShellScriptBin "ingress-start-pre" ''
          export PATH="${makeBinPath [ pkgs.coreutils ]}"
          set -exuo pipefail
          cp /etc/ssl/certs/cert-key.pem consul-key.pem
          cp /etc/ssl/certs/full.pem consul-ca.pem
          cat consul-ca.pem consul-key.pem > consul-crt.pem

          cat /etc/ssl/certs/${config.cluster.domain}-{cert,key}.pem \
            ${../lib/letsencrypt.pem} \
          > acme-full.pem

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
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      };

      path = with pkgs; [ consul consul-template vault-bin gawk glibc ];

      environment = {
        CONSUL_CACERT = "/etc/ssl/certs/full.pem";
        CONSUL_CLIENT_CERT = "/etc/ssl/certs/cert.pem";
        CONSUL_CLIENT_KEY = "consul-key.pem";
        CONSUL_HTTP_ADDR = "https://127.0.0.1:8501";
        CONSUL_HTTP_SSL = "true";
        inherit (config.environment.variables) VAULT_CACERT;
      };

      script = ''
        set -euo pipefail

        VAULT_TOKEN="$(vault login -method aws -no-store -token-only)"
        export VAULT_TOKEN
        CONSUL_HTTP_TOKEN="$(vault read -field token consul/creds/consul-server-default)"
        export CONSUL_HTTP_TOKEN

        set -x

        exec consul-template -log-level debug -config ${haproxyIngress}
      '';
    };
  };
}
