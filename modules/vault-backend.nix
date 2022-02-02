{ lib, config, pkgs, ... }:
let cfg = config.services.vault-backend;
in {
  options = {
    services.vault-backend = {
      enable = lib.mkEnableOption "Enable the Terraform Vault Backend";
      listen = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0:8080";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.vault-backend = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        VAULT_URL = "https://${config.cluster.coreNodes.core-1.privateIP}:8200";
        VAULT_PREFIX = "vbk"; # the prefix used when storing the secrets
        LISTEN_ADDRESS = cfg.listen;
      };

      serviceConfig = let
        execStartPre = pkgs.writeBashBinChecked "vault-backend-pre" ''
          set -exuo pipefail
          export PATH="${lib.makeBinPath [ pkgs.coreutils ]}"

          cp /etc/ssl/certs/{cert,cert-key}.pem .
          chown --reference . --recursive .
        '';
      in {
        ExecStartPre = "!${execStartPre}/bin/vault-backend-pre";
        ExecStart = "${pkgs.vault-backend}/bin/vault-backend";

        DynamicUser = true;
        Group = "vault-backend";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = "read-only";
        ProtectSystem = "full";
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitBurst = 3;
        StateDirectory = "vault-backend";
        TimeoutStopSec = "30s";
        User = "vault-backend";
        WorkingDirectory = "/var/lib/vault-backend";
      };
    };

    services.ingress-config = {
      extraHttpsFrontendConfig = ''
        acl is_vbk hdr(host) -i vbk.${config.cluster.domain}
        use_backend vbk if is_vbk
      '';

      extraConfig = ''
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

        backend vbk
          mode http
          server ipv4 127.0.0.1:8080
      '';
    };
  };
}

